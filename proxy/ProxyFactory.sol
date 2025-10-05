// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ProxyFactory
 * @dev Factory contract for deploying UUPS proxies with deterministic addresses
 * 
 * Features:
 * - Deploy UUPS proxies with CREATE2
 * - Deterministic proxy addresses
 * - Implementation management
 * - Batch deployment
 * - Proxy registry
 * 
 * Security Features:
 * - Access control for deployments
 * - Implementation whitelist
 * - Deployment tracking
 */
contract ProxyFactory is Ownable {
    /// @dev Mapping from implementation address to approval status
    mapping(address => bool) public approvedImplementations;
    
    /// @dev Array of all deployed proxies
    address[] public deployedProxies;
    
    /// @dev Mapping from proxy address to implementation
    mapping(address => address) public proxyToImplementation;
    
    /// @dev Mapping from deployer to deployed proxies
    mapping(address => address[]) public userProxies;
    
    /// @dev Mapping from salt to proxy address
    mapping(bytes32 => address) public saltToProxy;

    event ImplementationApproved(address indexed implementation, bool approved);
    event ProxyDeployed(
        address indexed proxy,
        address indexed implementation,
        address indexed deployer,
        bytes32 salt
    );

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Approve/disapprove an implementation for deployment
     * @param implementation Implementation address
     * @param approved Whether to approve the implementation
     */
    function setImplementationApproval(address implementation, bool approved) external onlyOwner {
        require(implementation != address(0), "Invalid implementation address");
        approvedImplementations[implementation] = approved;
        emit ImplementationApproved(implementation, approved);
    }

    /**
     * @dev Deploy a new UUPS proxy
     * @param implementation Implementation contract address
     * @param data Initialization data
     * @param salt Salt for CREATE2 deployment
     * @return proxy Address of deployed proxy
     */
    function deployProxy(
        address implementation,
        bytes calldata data,
        bytes32 salt
    ) external returns (address proxy) {
        require(approvedImplementations[implementation], "Implementation not approved");
        require(saltToProxy[salt] == address(0), "Salt already used");

        // Deploy proxy using CREATE2
        bytes memory bytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(implementation, data)
        );

        assembly {
            proxy := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
            if iszero(proxy) {
                revert(0, 0)
            }
        }

        // Record deployment
        deployedProxies.push(proxy);
        proxyToImplementation[proxy] = implementation;
        userProxies[msg.sender].push(proxy);
        saltToProxy[salt] = proxy;

        emit ProxyDeployed(proxy, implementation, msg.sender, salt);
    }

    /**
     * @dev Batch deploy multiple proxies
     * @param implementations Array of implementation addresses
     * @param datas Array of initialization data
     * @param salts Array of salts
     * @return proxies Array of deployed proxy addresses
     */
    function batchDeployProxies(
        address[] calldata implementations,
        bytes[] calldata datas,
        bytes32[] calldata salts
    ) external returns (address[] memory proxies) {
        require(
            implementations.length == datas.length &&
            datas.length == salts.length,
            "Array length mismatch"
        );
        require(implementations.length <= 10, "Too many deployments");

        proxies = new address[](implementations.length);
        
        for (uint256 i = 0; i < implementations.length; i++) {
            proxies[i] = deployProxy(implementations[i], datas[i], salts[i]);
        }
    }

    /**
     * @dev Predict proxy address for given parameters
     * @param implementation Implementation address
     * @param data Initialization data
     * @param salt Salt for CREATE2
     * @return predicted Predicted proxy address
     */
    function predictProxyAddress(
        address implementation,
        bytes calldata data,
        bytes32 salt
    ) external view returns (address predicted) {
        bytes memory bytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(implementation, data)
        );

        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(bytecode)
            )
        );

        predicted = address(uint160(uint256(hash)));
    }

    /**
     * @dev Get all proxies deployed by a user
     * @param user User address
     * @return Array of proxy addresses
     */
    function getUserProxies(address user) external view returns (address[] memory) {
        return userProxies[user];
    }

    /**
     * @dev Get total number of deployed proxies
     * @return Number of deployed proxies
     */
    function getDeployedProxiesCount() external view returns (uint256) {
        return deployedProxies.length;
    }

    /**
     * @dev Get deployed proxies in a range
     * @param start Start index
     * @param count Number of proxies to return
     * @return Array of proxy addresses
     */
    function getDeployedProxies(uint256 start, uint256 count) 
        external 
        view 
        returns (address[] memory) 
    {
        require(start < deployedProxies.length, "Start index out of bounds");
        
        uint256 end = start + count;
        if (end > deployedProxies.length) {
            end = deployedProxies.length;
        }
        
        address[] memory result = new address[](end - start);
        for (uint256 i = start; i < end; i++) {
            result[i - start] = deployedProxies[i];
        }
        
        return result;
    }

    /**
     * @dev Check if a proxy was deployed by this factory
     * @param proxy Proxy address to check
     * @return Whether proxy was deployed by this factory
     */
    function isProxyDeployed(address proxy) external view returns (bool) {
        return proxyToImplementation[proxy] != address(0);
    }

    /**
     * @dev Get implementation address for a proxy
     * @param proxy Proxy address
     * @return Implementation address
     */
    function getProxyImplementation(address proxy) external view returns (address) {
        return proxyToImplementation[proxy];
    }
}
