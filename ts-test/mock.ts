import {
  ASSOCIATED_TOKEN_PROGRAM_ID,
  AccountLayout,
  TOKEN_PROGRAM_ID,
} from "@solana/spl-token";
import { PublicKey } from "@solana/web3.js";
import {
  PerChainQueryRequest,
  QueryProxyMock,
  QueryRequest,
  QueryResponse,
  SolanaPdaQueryRequest,
  SolanaPdaQueryResponse,
  signaturesToEvmStruct,
} from "@wormhole-foundation/wormhole-query-sdk";
import base58 from "bs58";
import { Wallet, getDefaultProvider } from "ethers";
import { OwnerVerifier__factory } from "../types/ethers-contracts";

(async () => {
  const SOLANA_RPC = "https://api.mainnet-beta.solana.com";
  const ETH_NETWORK = "http://localhost:8545";
  const ANVIL_FORK_KEY =
    "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
  const WORMHOLE_ADDRESS = "0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B";
  const THIRTY_MINUTES = 60 * 30;
  const owner = new PublicKey("99mjQz6jfKpZw5dE3Bxq1RUV311u2EBG4mSKAH49CEep");
  const mint = new PublicKey("FudkRodUCGiK2xs5egx9YpSP4iyQsfr7SsEVSRAkj8qA");
  const mintHex = `0x${mint.toBuffer().toString("hex")}`;
  // explicitly implement `getAssociatedTokenAddressSync` from @solana/spl-token
  // https://github.com/solana-labs/solana-program-library/blob/d72289c79/token/js/src/state/mint.ts#L190
  const programId = ASSOCIATED_TOKEN_PROGRAM_ID;
  const seeds = [owner, TOKEN_PROGRAM_ID, mint];
  const [address, bump] = PublicKey.findProgramAddressSync(
    seeds.map((seed) => seed.toBuffer()),
    programId
  );
  console.log(
    "\nPDA input ",
    programId.toString(),
    seeds.map((seed) => seed.toString())
  );
  console.log("\nPDA output", address.toString(), bump);

  console.log(`\nMocking query using ${SOLANA_RPC}\n`);
  const mock = new QueryProxyMock({
    1: SOLANA_RPC,
  });
  const query = new QueryRequest(42, [
    new PerChainQueryRequest(
      1,
      new SolanaPdaQueryRequest("finalized", [
        {
          programAddress: programId.toBytes(),
          seeds: seeds.map((seed) => seed.toBytes()),
        },
      ])
    ),
  ]);
  const resp = await mock.mock(query);
  // console.log(resp);

  const queryResponse = QueryResponse.from(Buffer.from(resp.bytes, "hex"));
  const solResponse = queryResponse.responses[0]
    .response as SolanaPdaQueryResponse;
  // console.log(queryResponse.responses[0].response);
  console.log("Account:", base58.encode(solResponse.results[0].account));
  console.log("Owner:  ", base58.encode(solResponse.results[0].owner));
  console.log(
    "Data:   ",
    Buffer.from(solResponse.results[0].data).toString("hex")
  );
  console.log("\n", AccountLayout.decode(solResponse.results[0].data), "\n");
  console.log(
    `\nDeploying OwnerVerifier ${WORMHOLE_ADDRESS} ${mintHex} ${THIRTY_MINUTES}\n`
  );
  const provider = getDefaultProvider(ETH_NETWORK);
  const signer = new Wallet(ANVIL_FORK_KEY, provider);
  const ownerVerifierFactory = new OwnerVerifier__factory(signer);
  const ownerVerifier = await ownerVerifierFactory.deploy(
    WORMHOLE_ADDRESS,
    mintHex,
    THIRTY_MINUTES
  );
  await ownerVerifier.waitForDeployment();
  console.log(`Deployed address ${await ownerVerifier.getAddress()}`);

  console.log(`\nPosting query\n`);
  const tx = await ownerVerifier.verifyOwner(
    `0x${resp.bytes}`,
    signaturesToEvmStruct(resp.signatures)
  );
  const receipt = await tx.wait();
  if (!receipt || receipt.logs.length < 1) {
    throw new Error("Unexpected receipt");
  }
  const result = ownerVerifier.interface.decodeEventLog(
    "OwnerVerified",
    receipt.logs[0].data,
    receipt.logs[0].topics
  );
  const blockTime = new Date(Number(result[1] / BigInt(1000))).toISOString();
  const ownerEvm = base58.encode(Buffer.from(result[2].substring(2), "hex"));
  const accountEvm = base58.encode(Buffer.from(result[3].substring(2), "hex"));
  console.log(`slotNumber ${result[0].toString()}`);
  console.log(`blockTime  ${blockTime} (${result[1].toString()})`);
  console.log(`owner      ${ownerEvm} (${result[2]})`);
  console.log(`account    ${accountEvm} (${result[3]})`);

  if (owner.toString() === ownerEvm && address.toString() === accountEvm) {
    console.log("\n✅ Owner verified successfully!");
  } else {
    throw new Error("Ownership verification failed");
  }

  provider.destroy();
})();
