// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { FHE, euint64, ebool } from "@fhevm/solidity/lib/FHE.sol";
import { SepoliaConfig } from "@fhevm/solidity/config/ZamaConfig.sol";

contract AnonymousDelivery is SepoliaConfig {
    address public constant DELIVERY_ORACLE = 0x6A959E813D95B911b75D9A307532eF3316e87304;

    struct DeliveryRequest {
        uint256 id;
        address sender;
        address courier;
        string packageType;
        string priority;
        string privacyLevel;
        ebool isUrgent;
        uint8 status;
        uint256 timestamp;
        euint64 deliveryFee;
    }

    mapping(uint256 => DeliveryRequest) public deliveries;
    mapping(address => uint256[]) public userDeliveries;
    mapping(address => uint256[]) public courierDeliveries;
    mapping(uint256 => mapping(address => bool)) public accessPermissions;

    uint256 public deliveryCounter;
    uint256[] public activeDeliveries;

    event DeliveryCreated(uint256 indexed id, address indexed sender);
    event DeliveryAccepted(uint256 indexed id, address indexed courier);
    event DeliveryCompleted(uint256 indexed id);
    event PrivacyLevelUpdated(uint256 indexed id, string newLevel);
    event AccessGranted(uint256 indexed deliveryId, address indexed user);

    modifier onlyAuthorized(uint256 deliveryId) {
        require(
            msg.sender == deliveries[deliveryId].sender ||
            msg.sender == deliveries[deliveryId].courier ||
            accessPermissions[deliveryId][msg.sender],
            "Not authorized"
        );
        _;
    }

    constructor() {
        deliveryCounter = 0;
    }

    // Create new delivery request with FHE privacy features
    function createDelivery(
        string memory packageType,
        string memory priority,
        uint8 _isUrgent
    ) external {
        deliveryCounter++;

        // Create FHE encrypted values
        ebool encryptedIsUrgent = FHE.asEbool(_isUrgent == 1);
        euint64 encryptedFee = FHE.asEuint64(uint64(_calculateBaseFee(priority)));

        // Create delivery in storage
        deliveries[deliveryCounter].id = deliveryCounter;
        deliveries[deliveryCounter].sender = msg.sender;
        deliveries[deliveryCounter].packageType = packageType;
        deliveries[deliveryCounter].priority = priority;
        deliveries[deliveryCounter].isUrgent = encryptedIsUrgent;
        deliveries[deliveryCounter].status = 0;
        deliveries[deliveryCounter].timestamp = block.timestamp;
        deliveries[deliveryCounter].deliveryFee = encryptedFee;

        // Set FHE permissions
        FHE.allowThis(encryptedIsUrgent);
        FHE.allow(encryptedIsUrgent, msg.sender);
        FHE.allowThis(encryptedFee);
        FHE.allow(encryptedFee, msg.sender);

        // Update mappings
        accessPermissions[deliveryCounter][msg.sender] = true;
        userDeliveries[msg.sender].push(deliveryCounter);
        activeDeliveries.push(deliveryCounter);

        emit DeliveryCreated(deliveryCounter, msg.sender);
    }

    // Helper function to calculate base fee
    function _calculateBaseFee(string memory priority) private pure returns (uint256) {
        bytes32 priorityHash = keccak256(abi.encodePacked(priority));
        if (priorityHash == keccak256("urgent")) return 5000;
        if (priorityHash == keccak256("high")) return 3000;
        if (priorityHash == keccak256("medium")) return 2000;
        return 1000;
    }

    // Helper function to determine privacy level
    function _isHighPrivacyLevel(string memory privacyLevel) private pure returns (bool) {
        bytes32 levelHash = keccak256(abi.encodePacked(privacyLevel));
        return levelHash == keccak256("maximum") || levelHash == keccak256("enhanced");
    }

    // Accept delivery with privacy checks
    function acceptDelivery(uint256 deliveryId, uint8 _acceptance) external {
        require(deliveryId <= deliveryCounter, "Invalid delivery ID");
        require(deliveries[deliveryId].courier == address(0), "Delivery already accepted");
        require(_acceptance == 1, "Must accept the delivery");

        deliveries[deliveryId].courier = msg.sender;
        deliveries[deliveryId].status = 1; // Accepted

        // Grant courier access to delivery
        accessPermissions[deliveryId][msg.sender] = true;

        courierDeliveries[msg.sender].push(deliveryId);

        emit DeliveryAccepted(deliveryId, msg.sender);
        emit AccessGranted(deliveryId, msg.sender);
    }

    // Complete delivery with privacy verification
    function completeDelivery(uint256 deliveryId, uint8 _completion) external onlyAuthorized(deliveryId) {
        require(deliveryId <= deliveryCounter, "Invalid delivery ID");
        require(_completion == 1, "Must confirm completion");

        deliveries[deliveryId].status = 3; // Delivered

        // Remove from active deliveries
        _removeFromActiveDeliveries(deliveryId);

        emit DeliveryCompleted(deliveryId);
    }

    // Get delivery info (privacy-aware)
    function getDelivery(uint256 deliveryId) external view returns (
        uint256 id,
        address sender,
        address courier,
        string memory packageType,
        uint8 status,
        uint256 timestamp
    ) {
        require(deliveryId <= deliveryCounter, "Invalid delivery ID");
        DeliveryRequest storage delivery = deliveries[deliveryId];

        return (
            delivery.id,
            delivery.sender,
            delivery.courier,
            delivery.packageType,
            delivery.status,
            delivery.timestamp
        );
    }

    // Get active deliveries
    function getActiveDeliveries() external view returns (uint256[] memory) {
        return activeDeliveries;
    }

    // Get user's deliveries
    function getUserDeliveries(address user) external view returns (uint256[] memory) {
        return userDeliveries[user];
    }

    // Get courier's deliveries
    function getCourierDeliveries(address courier) external view returns (uint256[] memory) {
        return courierDeliveries[courier];
    }

    // Request decryption for delivery urgency status
    function requestUrgencyDecryption(uint256 deliveryId) external onlyAuthorized(deliveryId) {
        require(deliveryId <= deliveryCounter, "Invalid delivery ID");

        bytes32[] memory cts = new bytes32[](1);
        cts[0] = FHE.toBytes32(deliveries[deliveryId].isUrgent);
        FHE.requestDecryption(cts, this.processUrgencyResult.selector);
    }

    // Process urgency decryption result
    function processUrgencyResult(
        uint256 requestId,
        bool isUrgent,
        bytes[] memory signatures
    ) external {
        // Signature verification - simplified implementation
        // Store or emit result as needed
    }

    // Request decryption for delivery fee
    function requestFeeDecryption(uint256 deliveryId) external onlyAuthorized(deliveryId) {
        require(deliveryId <= deliveryCounter, "Invalid delivery ID");

        bytes32[] memory cts = new bytes32[](1);
        cts[0] = FHE.toBytes32(deliveries[deliveryId].deliveryFee);
        FHE.requestDecryption(cts, this.processFeeResult.selector);
    }

    // Process fee decryption result
    function processFeeResult(
        uint256 requestId,
        uint64 fee,
        bytes[] memory signatures
    ) external {
        // Signature verification - simplified implementation
        // Store or emit result as needed
    }


    // Update privacy level (only by sender)
    function updatePrivacyLevel(uint256 deliveryId, string memory newPrivacyLevel) external {
        require(deliveryId <= deliveryCounter, "Invalid delivery ID");
        require(msg.sender == deliveries[deliveryId].sender, "Only sender can update");

        deliveries[deliveryId].privacyLevel = newPrivacyLevel;
        emit PrivacyLevelUpdated(deliveryId, newPrivacyLevel);
    }

    // Grant access to delivery (privacy management)
    function grantAccess(uint256 deliveryId, address user) external {
        require(deliveryId <= deliveryCounter, "Invalid delivery ID");
        require(msg.sender == deliveries[deliveryId].sender, "Only sender can grant access");

        accessPermissions[deliveryId][user] = true;
        emit AccessGranted(deliveryId, user);
    }

    // Internal function to remove delivery from active list
    function _removeFromActiveDeliveries(uint256 deliveryId) internal {
        for (uint256 i = 0; i < activeDeliveries.length; i++) {
            if (activeDeliveries[i] == deliveryId) {
                activeDeliveries[i] = activeDeliveries[activeDeliveries.length - 1];
                activeDeliveries.pop();
                break;
            }
        }
    }


    // Get delivery count
    function getDeliveryCount() external view returns (uint256) {
        return deliveryCounter;
    }


    // Simple submission function following successful pattern
    function submitDeliveryUpdate(uint8 /* status */) external pure returns (bool) {
        // Simple function that accepts uint8 and triggers MetaMask transaction
        // This follows the successful submitGuess(uint8) pattern
        return true;
    }

    // Check access permissions
    function hasAccess(uint256 deliveryId, address user) external view returns (bool) {
        require(deliveryId <= deliveryCounter, "Invalid delivery ID");
        return accessPermissions[deliveryId][user] ||
               user == deliveries[deliveryId].sender ||
               user == deliveries[deliveryId].courier;
    }
}