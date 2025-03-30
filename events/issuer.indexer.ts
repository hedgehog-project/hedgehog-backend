import { db } from "../db";
import { assets, kyc, transactions } from "../db/schema";
import { issuerFireStore } from "../lib/stores";
import { indexFirestore } from "./utils";


await indexFirestore({
    contract: 'issuer',
    processor: async (key, data) => {
        console.log("Processing key", key)
        // console.log("Processing data", data)
        switch (data.type) {
            case "AssetMinted": {
                console.log("Asset Minted", data)

                break
            }
            case "AssetBurned": {
                console.log("Asset Burned", data)
                break
            }
            case "KYCGranted": {
                console.log("KYC Granted", data)
                const existing = await db.query.kyc.findFirst({
                    where: (fields, ops) => ops.eq(fields.account, data.account)
                })
                if (existing) {
                    console.log("KYC already granted")
                    break
                }
                await db.insert(kyc).values({
                    account: data.account,
                    token: data.token,
                })
                break
            }
            case "AssetPurchased": {
                console.log("Asset Purchased", data)
                await db.insert(transactions).values({
                    hash: data.hash,
                    account: data.buyer,
                    token: data.asset,
                    amount: data.amount,
                    type: "buy",
                    timestamp: data.timestamp
                })
                break
            }
            case "AssetSold": {
                console.log("Asset Sold", data)
                await db.insert(transactions).values({
                    hash: data.hash,
                    account: data.seller,
                    token: data.asset,
                    amount: data.amount,
                    type: "sell",
                    timestamp: data.timestamp
                })
                break
            }
            case "AssetCreated": {
                console.log("Asset Created", data)
                await db.insert(assets).values({
                    token: data.token,
                    name: data.name,
                    symbol: data.symbol,
                    timestamp: data.timestamp
                })
                break
            }
            default: {
                console.log("Unknown event type", data.type)
            }
        }
    },
    store: issuerFireStore
})