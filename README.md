# Aptos NFT Marketplace Contract

Vexpy is Explore, collect and sell Arts & NFTs. Base on Aptos blockchain, inspired by Opensea. hatched by Tonotice.

## **Getting started**

1. Initialize the aptos configuration, if you don't already have it
```shell
# create marketplace addr
aptos init --profile marketplace
```

2. Fund with faucet
```shell
# faucet
aptos account fund-with-faucet --account marketplace
```

3. Compile contract
```shell
aptos move compile --named-addresses lotus=marketplace
```

4. Test Contract

```shell
# test
aptos move test --named-addresses lotus=marketplace
```

5. Publish Contract to DevNet/TestNet
```shell

# publish
aptos move publish --included-artifacts none --named-addresses lotus=marketplace --profile=marketplace
```

6. marketplace addr call contract `initial_market_script`

```shell
aptos move run --function-id 'marketplace::Marketplace::initial_market_script' --profile=marketplace
```

## **Features**

- [x] initial market
- [x] batch list token
- [x] batch delist token
- [x] batch buy token
- [x] change token price
- [x] make offer
- [x] cancel offer
- [x] accept offer
- [x] claim accept token offer
- [x] inital auction
- [x] bid
- [x] claim auction token(buyer)
- [x] claim action coin(seller)

## **Contributing**

Bug report or pull request are welcome.

## **Make a pull request**

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

Please write unit test with your code if necessary.

## **License**

web3 is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
