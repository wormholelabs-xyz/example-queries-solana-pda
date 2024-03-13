// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import "wormhole-solidity-sdk/interfaces/IWormhole.sol";
import "wormhole-solidity-sdk/libraries/BytesParsing.sol";
import "wormhole-solidity-sdk/QueryResponse.sol";
import "../src/OwnerVerifier.sol";
import {WormholeMock} from "wormhole-solidity-sdk/testing/helpers/WormholeMock.sol";

contract CounterTest is Test {
    using BytesParsing for bytes;
    
    event OwnerVerified(
        uint64 solanaSlotNumber,
        uint64 solanaBlockTime,
        bytes32 owner,
        bytes32 account
    );

    OwnerVerifier public ownerVerifier;
    
    uint256 constant MOCK_GUARDIAN_PRIVATE_KEY = 0xcfb12303a19cde580bb4dd771639b0d26bc68353645571a8cff516ab2ee113a0;
    uint8 sigGuardianIndex = 0;

    uint256 THIRTY_MINUTES = 60*30;
    bytes32 mockMintAddress = 0xdd7f5ef910be9be4a65464a27a265c4cac70efc81998cfa1ff2ec0893f7be045;

    // some happy case defaults
    bytes mockMainnetResponse = hex"0100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c0010000002a01000105000000b30000000966696e616c697a6564000000000000000000000000000000000000000000000000018c97258f4e2489f1bb3d1029148e0d830b5a1399daff1084048e7bd8dbe9f8590300000020791cb83d8a3d0a4c1d943ae5c0c286af78102b3c01439165555f9cf03687b2fd0000002006ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a900000020dd7f5ef910be9be4a65464a27a265c4cac70efc81998cfa1ff2ec0893f7be045010001050000012c000000000f1d330800061368235ba8c0010fd341a2bd4679eff53844dd501d73b28441f5a9970d05a511146c4385d1560181cae12d89039c4eec644e0d29b609e5661a5bff917ea00144e0f959592a9389fe00000000001f1df0ffffffffffffffff0006ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a9000000a5dd7f5ef910be9be4a65464a27a265c4cac70efc81998cfa1ff2ec0893f7be045791cb83d8a3d0a4c1d943ae5c0c286af78102b3c01439165555f9cf03687b2fd0100000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
    uint8 mockMainnetSigV = 0x1c;
    bytes32 mockMainnetSigR = 0x38e486741c311b72217f4a6f4d7bcaf20362a003c09614d5119a2ff93c2e428a;
    bytes32 mockMainnetSigS = 0x27748cb5c112494a38eb4571e29a90774cb293ebafb404605b1b26f003036e04;
    uint64 mockSlot = 253571848;
    uint64 mockBlockTime = 1710187851000000;
    bytes32 mockOwner = 0x791cb83d8a3d0a4c1d943ae5c0c286af78102b3c01439165555f9cf03687b2fd;
    bytes32 mockAccount = 0x81cae12d89039c4eec644e0d29b609e5661a5bff917ea00144e0f959592a9389;
    
    function setUp() public {
        vm.warp(mockBlockTime/1_000_000);
        WormholeMock wormholeMock = new WormholeMock();
        ownerVerifier = new OwnerVerifier(
            address(wormholeMock), 
            mockMintAddress,
            THIRTY_MINUTES
        );
    }

    function test_reverse_involutive(uint64 i) public {
        assertEq(ownerVerifier.reverse(ownerVerifier.reverse(i)), i);
    }

    function test_reverse() public {
        assertEq(ownerVerifier.reverse(0x0123456789ABCDEF), 0xEFCDAB8967452301);
    }

    function getSignature(bytes memory response) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 responseDigest = ownerVerifier.getResponseDigest(response);
        (v, r, s) = vm.sign(MOCK_GUARDIAN_PRIVATE_KEY, responseDigest);
    }

    function test_getSignature() public {
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = getSignature(mockMainnetResponse);
        assertEq(sigV, mockMainnetSigV);
        assertEq(sigR, mockMainnetSigR);
        assertEq(sigS, mockMainnetSigS);
    }

    function test_valid_query() public {
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = getSignature(mockMainnetResponse);
        IWormhole.Signature[] memory signatures = new IWormhole.Signature[](1);
        signatures[0] = IWormhole.Signature({r: sigR, s: sigS, v: sigV, guardianIndex: sigGuardianIndex});

        vm.expectEmit();
        emit OwnerVerified(mockSlot, mockBlockTime, mockOwner, mockAccount);
        ownerVerifier.verifyOwner(mockMainnetResponse, signatures);
    }

    function test_stale_update_reverts() public {
        vm.warp((mockBlockTime/1_000_000)+THIRTY_MINUTES+1);
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = getSignature(mockMainnetResponse);
        IWormhole.Signature[] memory signatures = new IWormhole.Signature[](1);
        signatures[0] = IWormhole.Signature({r: sigR, s: sigS, v: sigV, guardianIndex: sigGuardianIndex});
        vm.expectRevert(StaleBlockTime.selector);
        ownerVerifier.verifyOwner(mockMainnetResponse, signatures);
    }

}
