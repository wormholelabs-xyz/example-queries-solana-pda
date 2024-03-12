// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.19;

import "./libraries/BytesParsing.sol";
import "./libraries/QueryResponse.sol";

error InvalidProgramId();         // 0x5a03abb4
error InvalidSeedsLength();       // 0xbbda9b77
error InvalidOwnerSeed();         // 0xc2afc972
error InvalidTokenProgramSeed();  // 0xa8802868
error InvalidMintSeed();          // 0xd00a71ee
error InvalidAmount();            // 0x2c5211c6
error InvalidAccountOwner();      // 0x36b1fa3a
error InvalidCommitmentLevel();   // 0xffe74dc8
error InvalidDataSlice();         // 0xf1b1ecf1
error InvalidForeignChainID();    // 0x4efe96a9
error UnexpectedDataLength();     // 0x9546c78e
error UnexpectedResultLength();   // 0x3a279ba1

contract OwnerVerifier is QueryResponse {
    using BytesParsing for bytes;

    event OwnerVerified(
        uint64 solanaSlotNumber,
        uint64 solanaBlockTime,
        bytes32 owner,
        bytes32 account
    );

    uint256 public immutable allowedUpdateStaleness;
    bytes32 public immutable mintAddress;

    uint16 public constant SOLANA_CHAIN_ID = 1;
    bytes12 public constant SOLANA_COMMITMENT_LEVEL = "finalized";
    // https://github.com/solana-labs/solana-program-library/blob/d72289c79/token/js/src/constants.ts
    // Buffer.from(base58.decode('TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA')).toString('hex')
    bytes32 public constant TOKEN_PROGRAM_ID = 0x06ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a9;
    // Buffer.from(base58.decode('ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL')).toString('hex')
    bytes32 public constant ASSOCIATED_TOKEN_PROGRAM_ID = 0x8c97258f4e2489f1bb3d1029148e0d830b5a1399daff1084048e7bd8dbe9f859;
    // https://github.com/solana-labs/solana-program-library/blob/d72289c79/token/js/src/state/account.ts#L68-L81
    uint64 public constant EXPECTED_DATA_OFFSET = 0;
    uint64 public constant EXPECTED_DATA_LENGTH = 0;
    // require("@solana/spl-token").AccountLayout.span
    uint public constant EXPECTED_ACCOUNT_LENGTH = 165;

    constructor(address _wormhole, bytes32 _mintAddress, uint256 _allowedUpdateStaleness) QueryResponse(_wormhole) {
        mintAddress = _mintAddress;
        allowedUpdateStaleness = _allowedUpdateStaleness;
    }

    function reverse(uint64 input) public pure returns (uint64 v) {
        v = input;
        // swap bytes
        v = ((v & 0xFF00FF00FF00FF00) >> 8) |
            ((v & 0x00FF00FF00FF00FF) << 8);
        // swap 2-byte long pairs
        v = ((v & 0xFFFF0000FFFF0000) >> 16) |
            ((v & 0x0000FFFF0000FFFF) << 16);
        // swap 4-byte long pairs
        v = (v >> 32) | (v << 32);
    }

    // @notice Takes the cross chain query response for the associated token account on Solana and emits an event.
    function verifyOwner(bytes memory response, IWormhole.Signature[] memory signatures) public {
        ParsedQueryResponse memory r = parseAndVerifyQueryResponse(response, signatures);
        if (r.responses.length != 1) {
            revert UnexpectedResultLength();
        }
        if (r.responses[0].chainId != SOLANA_CHAIN_ID) {
            revert InvalidForeignChainID();
        }
        SolanaPdaQueryResponse memory s = parseSolanaPdaQueryResponse(r.responses[0]);
        if (s.requestCommitment.length > 12 || bytes12(s.requestCommitment) != SOLANA_COMMITMENT_LEVEL) {
            revert InvalidCommitmentLevel();
        }
        if (s.requestDataSliceOffset != EXPECTED_DATA_OFFSET || s.requestDataSliceLength != EXPECTED_DATA_LENGTH) {
            revert InvalidDataSlice();
        }
        // this could also handle any number of assiciated token accounts, but to keep the example simple will only handle one at a time
        if (s.results.length != 1) {
            revert UnexpectedResultLength();
        }
        if (s.results[0].programId != ASSOCIATED_TOKEN_PROGRAM_ID) {
            revert InvalidProgramId();
        }
        if (s.results[0].seeds.length != 3) {
            revert InvalidSeedsLength();
        }
        if (s.results[0].seeds[0].length != 32) {
            revert InvalidOwnerSeed();
        }
        if (s.results[0].seeds[1].length != 32 || bytes32(s.results[0].seeds[1]) != TOKEN_PROGRAM_ID) {
            revert InvalidTokenProgramSeed();
        }
        if (s.results[0].seeds[2].length != 32 || bytes32(s.results[0].seeds[2]) != mintAddress) {
            revert InvalidMintSeed();
        }
        if (s.results[0].owner != TOKEN_PROGRAM_ID) {
            revert InvalidAccountOwner();
        }
        validateBlockTime(s.blockTime, allowedUpdateStaleness >= block.timestamp ? 0 : block.timestamp - allowedUpdateStaleness);
        if (s.results[0].data.length != EXPECTED_ACCOUNT_LENGTH) {
            revert UnexpectedDataLength();
        }
        bytes32 _mint;
        bytes32 _owner;
        uint64 _amountLE;
        uint offset = 0;
        (_mint, offset) = s.results[0].data.asBytes32Unchecked(offset);
        (_owner, offset) = s.results[0].data.asBytes32Unchecked(offset);
        (_amountLE, offset) = s.results[0].data.asUint64Unchecked(offset);
        
        uint64 amount = reverse(_amountLE);

        if (amount != 1) {
            revert InvalidAmount();
        }

        emit OwnerVerified(s.slotNumber, s.blockTime, bytes32(s.results[0].seeds[0]), s.results[0].account);
    }
}
