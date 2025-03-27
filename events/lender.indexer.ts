import { db } from "../db";
import { assets, kyc, lendingReserves, liquidations, loanRepayment, loans, providedLiquidity, transactions, withdrawnLiquidity } from "../db/schema";
import {lenderFireStore } from "../lib/stores";
import { generateId } from "../lib/utils";
import { indexFirestore } from "./utils";


indexFirestore({
    contract: 'lender',
    ignoreLastCommit: true,
    processor: async (key, data) => {
        console.log("Processing key", key)
        console.log("Processing data", data)
        switch (data.type) {
            case "AssetLendingReserveCreated": {
                
                await db.insert(lendingReserves).values({
                    token: data.token,
                    asset: data.asset,
                    name: data.name,
                    symbol: data.name, // TODO: Fix to use symbol
                    timestamp: data.timestamp
                })
                break;
            }
            case "LoanRecorded": {
                await db.insert(loans).values({
                    account: data.borrower,
                    collateralAmount: data.collateralAmountAsset,
                    collateralAsset: data.token,
                    id: generateId("loan"),
                    liquidationPrice: data.liquidationUSDCPrice,
                    loanAmountUSDC: data.loanAmountUSDC,
                    repaymentAmount: data.repayAmount,
                    timestamp: data.timestamp
                })
                break;
            }
            case "LoanLiquidated": {
                const borrower = data.borrower
                const existingLoan = await db.query.loans.findFirst({
                    where(fields, operators) {
                        return operators.and(
                            operators.eq(fields.account, borrower),
                            operators.eq(fields.collateralAsset, data.token)
                        )
                    },
                })

                if (existingLoan) {
                    await db.insert(liquidations).values({
                        id: generateId("liquidation"),
                        account: borrower,
                        loanId: existingLoan.id,
                        timestamp: data.timestamp
                    })
                }
                break;
            }
            case "LoanRepaid": {
                const borrower = data.borrower
                const existingLoan = await db.query.loans.findFirst({
                    where(fields, operators) {
                        return operators.and(
                            operators.eq(fields.account, borrower),
                            operators.eq(fields.collateralAsset, data.token)
                        )
                    },
                })

                if (existingLoan) {
                    await db.insert(loanRepayment).values({
                        id: generateId("repayment"),
                        account: borrower,
                        loanId: existingLoan.id,
                        token: data.token,
                        timestamp: data.timestamp
                    })
                }
                break;
            }
            case "LiquidityProvided": {
                await db.insert(providedLiquidity).values({
                    id: generateId("liquidity"),
                    account: data.user,
                    asset: data.asset,
                    amount: data.amount,
                    timestamp: data.timestamp
                })
                break;
            }
            case "LiquidityWithdrawn": {
                await db.insert(withdrawnLiquidity).values({
                    id: generateId("withdrawal"),
                    account: data.user,
                    asset: data.asset,
                    amount: data.amount,
                    timestamp: data.timestamp
                })
                break;
            }
            default: {
                console.log("Unknown event type", data)
                break
            }
        }
    },
    store: lenderFireStore
})