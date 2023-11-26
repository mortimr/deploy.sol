// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import "../src/Deployer.sol";

contract Dummy {
    address public ok;

    constructor(address _ok) {
        ok = _ok;
    }

    function getName() external pure returns (string memory) {
        return "dummy";
    }
}

contract DeployConfig is Test {
    function eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function getDeploymentName() public view returns (string memory deploymentName) {
        deploymentName = vulcan.hevm.envString("FOUNDRY_DEPLOYMENT_NAME");
        if (bytes(deploymentName).length == 0) {
            revert("ERR=FOUNDRY_DEPLOYMENT_NAME IS UNDEFINED");
        }
    }

    function getDeploymentPath() external view returns (string memory) {
        string memory deploymentName = getDeploymentName();
        if (eq(deploymentName, "local")) {
            return "/deployments/local";
        } else if (eq(deploymentName, "mainnet")) {
            return "/deployments/mainnet";
        } else {
            revert("ERR=INVALID FOUNDRY_DEPLOYMENT_NAME VALUE");
        }
    }

    function shouldWrite() external view returns (bool) {
        return vulcan.hevm.envBool("FOUNDRY_WRITE_ARTIFACTS");
    }
}

contract DummyDeployer is Deployer {
    DeployConfig internal dc;

    function setUp() public {
        dc = new DeployConfig();
        setDeploymentPath(dc.getDeploymentPath());
        setShouldWrite(dc.shouldWrite());
    }

    function run() public {
        _00_deploy_Dummy();
        _01_deploy_another_Dummy();
        _02_merge_artifacts();
        _03_create_abi_artifacts();

        done();
    }

    function _00_deploy_Dummy() internal {
        address dummy;
        if ((dummy = startDeployment("Dummy_v0", "Dummy.deploy.sol/Dummy.json")) == address(0)) {
            dummy = store(address(new Dummy(address(0))));
        }
    }

    function _01_deploy_another_Dummy() internal {
        address dummy;
        if ((dummy = startDeployment("Dummy_v1", "Dummy.deploy.sol/Dummy.json")) == address(0)) {
            address dummy_v0 = getDeployment("Dummy_v0");
            dummy = store(address(new Dummy(dummy_v0)));
        }
    }

    function _02_merge_artifacts() internal {
        mergeArtifacts("Dummy_v1", "Dummy_v0", "Dummy_v2");
    }

    function _03_create_abi_artifacts() internal {
        createAbiArtifact("Dummy_v2", "Dummy");
    }
}
