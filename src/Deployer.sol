// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import "vulcan/test.sol";
import "./LibRLP.sol";

contract Deployer is Test {
    bool public shouldWriteArtifacts;

    string public deploymentPath;
    string public artifactsPath;

    string public currentDeployment = "";
    string public currentArtifact = "";
    string public deploymentArtifactPath = "";

    string[] public newArtifacts;
    mapping(string => bool) isNewArtifact;

    constructor() {
        setDeploymentPath("/deployments");
        setArtifactsPath("/out");
    }

    function setShouldWrite(bool value) internal {
        shouldWriteArtifacts = value;
    }

    function setDeploymentPath(string memory _path) internal {
        deploymentPath = string.concat(vulcan.hevm.projectRoot(), _path, "/");
        console.log("set deployment path", deploymentPath);
    }

    function setArtifactsPath(string memory _path) internal {
        artifactsPath = string.concat(vulcan.hevm.projectRoot(), _path, "/");
        console.log("set artifacts path", deploymentPath);
    }

    function ensureDeploymentArtifactPathExists() internal {
        commands.run(["mkdir", "-p", deploymentPath]);
    }

    function getJsonKey(string memory _fileName, string memory _key) internal returns (string memory) {
        CommandOutput memory output =
            commands.run(["jq", "-c", string.concat(".", _key), _fileName]).expect("jq command failed");

        return string(output.stdout);
    }

    function getRawJsonKey(string memory _fileName, string memory _key) internal returns (string memory) {
        string[] memory call = new string[](4);
        call[0] = "jq";
        call[1] = "-cr";
        call[2] = string.concat(".", _key);
        call[3] = _fileName;

        CommandOutput memory output =
            commands.run(["jq", "-cr", string.concat(".", _key), _fileName]).expect("jq command failed");
        return string(output.stdout);
    }

    function slice(bytes memory _bytes, uint256 _start, uint256 _length) internal pure returns (bytes memory) {
        require(_length + 31 >= _length, "slice_overflow");
        require(_bytes.length >= _start + _length, "slice_outOfBounds");

        bytes memory tempBytes;

        assembly {
            switch iszero(_length)
            case 0 {
                // Get a location of some free memory and store it in tempBytes as
                // Solidity does for memory variables.
                tempBytes := mload(0x40)

                // The first word of the slice result is potentially a partial
                // word read from the original array. To read it, we calculate
                // the length of that partial word and start copying that many
                // bytes into the array. The first word we copy will start with
                // data we don't care about, but the last `lengthmod` bytes will
                // land at the beginning of the contents of the new array. When
                // we're done copying, we overwrite the full first word with
                // the actual length of the slice.
                let lengthmod := and(_length, 31)

                // The multiplication in the next line is necessary
                // because when slicing multiples of 32 bytes (lengthmod == 0)
                // the following copy loop was copying the origin's length
                // and then ending prematurely not copying everything it should.
                let mc := add(add(tempBytes, lengthmod), mul(0x20, iszero(lengthmod)))
                let end := add(mc, _length)

                for {
                    // The multiplication in the next line has the same exact purpose
                    // as the one above.
                    let cc := add(add(add(_bytes, lengthmod), mul(0x20, iszero(lengthmod))), _start)
                } lt(mc, end) {
                    mc := add(mc, 0x20)
                    cc := add(cc, 0x20)
                } { mstore(mc, mload(cc)) }

                mstore(tempBytes, _length)

                //update free-memory pointer
                //allocating the array padded to 32 bytes like the compiler does now
                mstore(0x40, and(add(mc, 31), not(31)))
            }
            //if we want a zero-length slice let's just return a zero-length array
            default {
                tempBytes := mload(0x40)
                //zero out the 32 bytes slice we are about to return
                //we need to do it because Solidity does not garbage collect
                mstore(tempBytes, 0)

                mstore(0x40, add(tempBytes, 0x20))
            }
        }

        return tempBytes;
    }

    function stringToAddress(bytes memory b) internal pure returns (address) {
        uint256 result = 0;
        for (uint256 i = 2; i < b.length; i++) {
            uint256 c = uint256(uint8(b[i]));
            if (c >= 48 && c <= 57) {
                result = result * 16 + (c - 48);
            }
            if (c >= 65 && c <= 90) {
                result = result * 16 + (c - 55);
            }
            if (c >= 97 && c <= 122) {
                result = result * 16 + (c - 87);
            }
        }
        return address(uint160(result));
    }

    function startDeployment(string memory _name, string memory _artifact) internal returns (address) {
        require(bytes(currentDeployment).length == 0, "ERR=START DEPLOYMENT WHILE ANOTHER IN PROCESS");
        ensureDeploymentArtifactPathExists();

        string memory currentDeploymentArtifactPath = string.concat(deploymentPath, _name, ".artifact.json");

        try vulcan.hevm.readFile(currentDeploymentArtifactPath) returns (string memory) {
            string memory addr = getJsonKey(currentDeploymentArtifactPath, "address");
            if (bytes(addr).length == 44) {
                address deployedAddress = stringToAddress(slice(bytes(addr), 1, 42));
                console.log("reusing address for", _name, deployedAddress);
                return deployedAddress;
            } else {
                revert("ERR=INVALID ADDRESS FROM ARTIFACT");
            }
        } catch {
            currentDeployment = _name;
            currentArtifact = string.concat(artifactsPath, _artifact);
            deploymentArtifactPath = string.concat(deploymentPath, _name, ".artifact.json");
            vulcan.hevm.startBroadcast();
            return address(0);
        }
    }

    function startYulDeployment(string memory _name) internal returns (address) {
        require(bytes(currentDeployment).length == 0, "ERR=START DEPLOYMENT WHILE ANOTHER IN PROCESS");
        ensureDeploymentArtifactPathExists();

        string memory currentDeploymentArtifactPath = string.concat(deploymentPath, _name, ".artifact.json");

        try vulcan.hevm.readFile(currentDeploymentArtifactPath) returns (string memory) {
            string memory addr = getJsonKey(currentDeploymentArtifactPath, "address");
            if (bytes(addr).length == 44) {
                address deployedAddress = stringToAddress(slice(bytes(addr), 1, 42));
                console.log("reusing address for", _name, deployedAddress);
                return deployedAddress;
            } else {
                revert("ERR=INVALID ADDRESS FROM ARTIFACT");
            }
        } catch {
            currentDeployment = _name;
            deploymentArtifactPath = string.concat(deploymentPath, _name, ".artifact.json");
            vulcan.hevm.startBroadcast();
            return address(0);
        }
    }

    function getDeployment(string memory _name) internal returns (address) {
        string memory addr = getJsonKey(string.concat(deploymentPath, _name, ".artifact.json"), "address");
        if (bytes(addr).length == 44) {
            return stringToAddress(slice(bytes(addr), 1, 42));
        } else {
            revert("ERR=INVALID ADDRESS FROM ARTIFACT");
        }
    }

    function hasDeployment(string memory _name) internal view returns (bool) {
        try vulcan.hevm.readFile(string.concat(deploymentPath, _name, ".artifact.json")) returns (string memory) {
            return true;
        } catch {
            return false;
        }
    }

    function store(address _contract) internal returns (address) {
        if (bytes(currentDeployment).length != 0) {
            vulcan.hevm.stopBroadcast();
            console.log("deployed", currentDeployment, "at", _contract);
            CommandOutput memory output = commands.run(
                [
                    "jq",
                    "-nSr",
                    "-r",
                    "--arg",
                    "address",
                    vulcan.hevm.toString(_contract),
                    "--argjson",
                    "abi",
                    getJsonKey(currentArtifact, "abi"),
                    string.concat(
                        "{\"address\": $address, \"abi\": $abi, \"bytecode\": ",
                        getJsonKey(currentArtifact, "bytecode.object"),
                        ", \"deployedBytecode\": ",
                        getJsonKey(currentArtifact, "deployedBytecode.object"),
                        "}"
                    )
                ]
            ).expect("jq command failed");
            string memory artifactContent = string(output.stdout);

            vulcan.hevm.writeFile(deploymentArtifactPath, artifactContent);
            console.log("stored deployment artifact at", deploymentArtifactPath);

            if (!isNewArtifact[deploymentArtifactPath]) {
                isNewArtifact[deploymentArtifactPath] = true;
                newArtifacts.push(deploymentArtifactPath);
            }

            currentDeployment = "";
            currentArtifact = "";
            deploymentArtifactPath = "";
        }
        return _contract;
    }

    function bytesToHex(bytes memory buffer) internal pure returns (string memory) {
        // Fixed buffer size for hexadecimal convertion
        bytes memory converted = new bytes(buffer.length * 2);

        bytes memory _base = "0123456789abcdef";

        for (uint256 i = 0; i < buffer.length; i++) {
            converted[i * 2] = _base[uint8(buffer[i]) / _base.length];
            converted[i * 2 + 1] = _base[uint8(buffer[i]) % _base.length];
        }

        return string(abi.encodePacked("0x", converted));
    }

    function storeYul(address _contract, bytes memory deploymentBytecode, bytes memory runtimeBytecode)
        internal
        returns (address)
    {
        if (bytes(currentDeployment).length != 0) {
            vulcan.hevm.stopBroadcast();
            console.log("deployed", currentDeployment, "at", _contract);
            CommandOutput memory output = commands.run(
                [
                    "jq",
                    "-nSr",
                    "-r",
                    "--arg",
                    "address",
                    vulcan.hevm.toString(_contract),
                    string.concat(
                        "{\"address\": $address, \"bytecode\": \"",
                        string(bytesToHex(deploymentBytecode)),
                        "\", \"deployedBytecode\": \"",
                        string(bytesToHex(runtimeBytecode)),
                        "\"}"
                    )
                ]
            ).expect("jq command failed");
            string memory artifactContent = string(output.stdout);

            vulcan.hevm.writeFile(deploymentArtifactPath, artifactContent);
            console.log("stored deployment artifact at", deploymentArtifactPath);

            if (!isNewArtifact[deploymentArtifactPath]) {
                isNewArtifact[deploymentArtifactPath] = true;
                newArtifacts.push(deploymentArtifactPath);
            }

            currentDeployment = "";
            currentArtifact = "";
            deploymentArtifactPath = "";
        }
        return _contract;
    }

    function done() internal {
        if (!shouldWriteArtifacts) {
            console.log("");
            console.log("shouldWriteArtifacts=false");
            for (uint256 idx = 0; idx < newArtifacts.length;) {
                vulcan.hevm.removeFile(newArtifacts[idx]);
                console.log("removing", newArtifacts[idx]);

                unchecked {
                    ++idx;
                }
            }
            console.log("");
            console.log("to save artifacts, do Deployer.setShouldWrite(true)");
        }
    }

    function predict(address deployer, uint256 _txCount, string[] memory _deployments)
        internal
        view
        returns (address)
    {
        for (uint256 idx; idx < _deployments.length;) {
            if (hasDeployment(_deployments[idx])) {
                --_txCount;
            }
            unchecked {
                ++idx;
            }
        }
        return LibRLP.computeAddress(deployer, _txCount);
    }

    function mergeArtifacts(
        string memory proxyDeployment,
        string memory implementationDeployment,
        string memory destinationDeployment
    ) internal {
        string memory proxyArtifactPath = string.concat(deploymentPath, proxyDeployment, ".artifact.json");
        string memory implementationArtifactPath =
            string.concat(deploymentPath, implementationDeployment, ".artifact.json");
        string memory destinationArtifactPath = string.concat(deploymentPath, destinationDeployment, ".artifact.json");

        console.log(
            string.concat(
                "merging ", proxyDeployment, " and ", implementationDeployment, " into ", destinationDeployment
            )
        );

        CommandOutput memory output = commands.run(
            [
                "bash",
                "-c",
                string.concat(
                    "echo $(cat ",
                    implementationArtifactPath,
                    " | jq .abi | sed '$d'),$(cat ",
                    proxyArtifactPath,
                    " | jq .abi | sed '1d') | jq"
                )
            ]
        ).expect("merge command failed");

        string memory mergedAbis = string(output.stdout);

        output = commands.run(
            [
                "jq",
                "-nSr",
                "-r",
                "--arg",
                "address",
                string(bytesToHex(bytes(getRawJsonKey(proxyArtifactPath, "address")))),
                "--argjson",
                "abi",
                mergedAbis,
                string.concat(
                    "{\"address\": $address, \"abi\": $abi, \"bytecode\": ",
                    getJsonKey(proxyArtifactPath, "bytecode"),
                    ", \"deployedBytecode\": ",
                    getJsonKey(proxyArtifactPath, "deployedBytecode"),
                    "}"
                )
            ]
        ).expect("jq command failed");
        string memory artifactContent = string(output.stdout);

        vulcan.hevm.writeFile(destinationArtifactPath, artifactContent);
    }

    function createAbiArtifact(string memory deploymentArtifact, string memory destinationAbiArtifact) internal {
        string memory artifactPath = string.concat(deploymentPath, deploymentArtifact, ".artifact.json");
        string memory abiArtifactPath = string.concat(deploymentPath, destinationAbiArtifact, ".abi.json");
        console.log(string.concat("create ", abiArtifactPath, " abi artifact from ", artifactPath));
        commands.run(["bash", "-c", string.concat("cat ", artifactPath, " | jq .abi > ", abiArtifactPath)]);
    }
}
