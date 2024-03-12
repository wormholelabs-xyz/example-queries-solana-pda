## Queries Solana PDA PoC

This is a demo of using [Wormhole Queries](https://wormhole.com/queries/) to check ownership of a Solana NFT on an EVM chain.

While this is a fairly simple example of checking the Solana owner of a single NFT, this could be chained with other queries to also:

- Read from another Solana program's PDA which allows Solana wallets to designate an EVM address
- Read the Metaplex metadata for the matching mint
- Read anything that is stored in any account on Solana

Learn more about developing with Queries in [the docs](https://docs.wormhole.com/wormhole/queries/getting-started).

Want to see another example of reading Solana accounts? Check out the [Solana Stake Pool](https://github.com/wormholelabs-xyz/example-queries-solana-stake-pool) example.

Want to verify EVM queries on Solana? Check out [Solana Queries Verification](https://github.com/wormholelabs-xyz/example-queries-solana-verify) example.

## Contract

The oracle contract at [`./src/OwnerVerifier.sol`](./src/OwnerVerifier.sol) is an immutable [QueryResponse](https://github.com/wormhole-foundation/wormhole/blob/main/ethereum/contracts/query/QueryResponse.sol) processor, which accepts valid queries for the designated token mint account via `verifyOwner()` and emits an event as long as the token account balance is exactly `1` and the Solana block time is not older than the configured `allowedStaleness`.

### Constructor

- `address _wormhole` - The address of the Wormhole core contract on this chain. Used to verify guardian signatures.
- `bytes32 _mintAddress` - The 32-byte address in hex of the SPL mint account on Solana. Only queries for that account will be accepted.
- `uint64 _allowedUpdateStaleness` - The time in seconds behind the current block time for which updates will be accepted (i.e. `updatePool` will not revert).

### verifyOwner

The `verifyOwner` method takes in the `response` and `signatures` from a Wormhole Query, performs validation, and emits an event.

The validation includes

- Verifying the guardian signatures
- Parsing the query response
- Response includes exactly 1 result
- Response is for the Solana (Wormhole) chain id
- Request commitment level is for `finalized`
- Request data slice is for entire [SPL token account](https://github.com/solana-labs/solana-program-library/blob/d72289c79/token/js/src/state/account.ts#L68-L81)
- Request PDA 0 is for the program `ASSOCIATED_TOKEN_PROGRAM_ID`
- Request PDA 0 has 3 seeds, all of length `32`, where 1 is `TOKEN_PROGRAM_ID` and 2 is the configured `mintAddress`
- Response account 0's owner is `TOKEN_PROGRAM_ID`
- Response time is at least `block.timestamp - allowedUpdateStaleness`

This then emits the following event

```solidity
event OwnerVerified(
    uint64 solanaSlotNumber,
    uint64 solanaBlockTime,
    bytes32 owner,
    bytes32 account
);
```

## Tests

### Unit Tests - Forge

[`./test/OwnerVerifier.t.sol`](./test/OwnerVerifier.t.sol) tests the following

- `reverse` method of the contract, which converts the `u64` fields stored in the Solana account from little-endian (Borsch) to big-endian (Solidity)
- `verifyOwner` positive test case, in which submitting a valid query updates the fields accordingly

#### Run

```bash
forge test
```

### Integration Tests - TypeScript

[`./ts-test/mock.ts`](./ts-test/mock.ts) performs fork testing by forking Ethereum mainnet, overriding the guardian set on the core contract, and mocking the Query Proxy / Guardian responses.

#### Setup

```bash
# Install dependencies
npm ci
# Generate bindings
forge build
npx typechain --target=ethers-v6 ./out/**/*.json
# Start anvil
anvil --fork-url https://ethereum.publicnode.com
# Override guardian set
npx @wormhole-foundation/wormhole-cli evm hijack -a 0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B -g 0xbeFA429d57cD18b7F8A4d91A2da9AB4AF05d0FBe
```

#### Run

```bash
npx tsx ./ts-test/mock.ts
```

## Deploy

The contract can be deployed with

```bash
forge create OwnerVerifier --private-key <YOUR_PRIVATE_KEY> --constructor-args <WORMHOLE_CORE_BRIDGE_ADDRESS> <MINT_ADDRESS_HEX> <ALLOWED_UPDATE_STALENESS>
```

So the deploy corresponding to the above integration test might look like

```bash
forge create OwnerVerifier --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --constructor-args 0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B 0xdd7f5ef910be9be4a65464a27a265c4cac70efc81998cfa1ff2ec0893f7be045 1800
```

---

⚠ **This software is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
implied. See the License for the specific language governing permissions and limitations under the License.**
