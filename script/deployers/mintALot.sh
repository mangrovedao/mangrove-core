export TO=0x3073A02460D7BE1A1C9afC60A059Ad8d788A4502
export AMOUNT_WITHOUT_DECIMALS=1000000000

TOKEN=USDT AMOUNT=$(cast ff 6 $AMOUNT_WITHOUT_DECIMALS) forge script --fork-url mumbai MumbaiFaucetSetLimit --broadcast
TOKEN=USDT AMOUNT=$(cast ff 6 $AMOUNT_WITHOUT_DECIMALS) TO="$TO" forge script --fork-url mumbai MumbaiFaucetMint --broadcast
TOKEN=USDT AMOUNT=$(cast ff 6 100000) forge script --fork-url mumbai MumbaiFaucetSetLimit --broadcast

TOKEN=WBTC AMOUNT=$(cast ff 8 $AMOUNT_WITHOUT_DECIMALS) forge script --fork-url mumbai MumbaiFaucetSetLimit --broadcast
TOKEN=WBTC AMOUNT=$(cast ff 8 $AMOUNT_WITHOUT_DECIMALS) TO="$TO" forge script --fork-url mumbai MumbaiFaucetMint --broadcast
TOKEN=WBTC AMOUNT=$(cast ff 8 3) forge script --fork-url mumbai MumbaiFaucetSetLimit --broadcast

TOKEN=WMATIC AMOUNT=$(cast ff 18 $AMOUNT_WITHOUT_DECIMALS) forge script --fork-url mumbai MumbaiFaucetSetLimit --broadcast
TOKEN=WMATIC AMOUNT=$(cast ff 18 $AMOUNT_WITHOUT_DECIMALS) TO="$TO" forge script --fork-url mumbai MumbaiFaucetMint --broadcast
TOKEN=WMATIC AMOUNT=$(cast ff 18 100000) forge script --fork-url mumbai MumbaiFaucetSetLimit --broadcast
