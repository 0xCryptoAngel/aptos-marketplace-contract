module lotus::Marketplace {

    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::timestamp;
    use aptos_framework::account;
    use aptos_framework::account::SignerCapability;
    use aptos_framework::guid;

    use std::signer;
    use std::option::{Self, Option, some};
    use std::string::String;
    use std::vector;
    use aptos_std::event::{Self, EventHandle};
    use aptos_std::table::{Self, Table};
    // use aptos_std::debug::{print};

    use aptos_token::token::{Self, Token, TokenId};
    
    // ERROR's
    const ERROR_INVALID_BUYER: u64 = 0;
    const ERROR_INSUFFICIENT_BID: u64 = 1;
    const ERROR_AUCTION_INACTIVE: u64 = 2;
    const ERROR_AUCTION_NOT_COMPLETE: u64 = 3;
    const ERROR_NOT_CLAIMABLE: u64 = 4;
    const ERROR_CLAIM_COINS_FIRST: u64 = 5;
    const ERROR_ALREADY_CLAIMED: u64 = 6;
    const ERROR_INVALID_SELLER: u64 = 7;
    const ERROR_ALREADY_LISTING: u64 = 8;
    const ERROR: u64 = 9;
    const ERROR_INVALID_OWNER:u64 = 10;
    const ERROR_NOT_ENOUGH_LENGTH:u64 = 11;
    const ERROR_ALREADY_OFFER:u64 = 12;
    const ERROR_EXPIRED_TIME_ACCEPT:u64 = 13;

    struct TokenCap has key {
        cap: SignerCapability,
    }

    struct MarketData has key {
        fee: u64,
        fund_address: address
    }

    // Set of data sent to the event stream during a listing of a token (for fixed price)
    struct ListEvent has drop, store {
        id: TokenId,
        amount: u64,
        timestamp: u64,
        listing_id: u64,
        seller_address: address,
        royalty_payee: address,
        royalty_numerator: u64,
        royalty_denominator: u64
    }

    struct DelistEvent has drop, store {
        id: TokenId,
        timestamp: u64,
        listing_id: u64,
        amount: u64,
        seller_address: address,
    }

    // Set of data sent to the event stream during a buying of a token (for fixed price)
    struct BuyEvent has drop, store {
        id: TokenId,
        timestamp: u64,
        listing_id: u64,
        seller_address: address,
        buyer_address: address
    }

    struct ListedItem has store {
        amount: u64,
        timestamp: u64,
        listing_id: u64,
        locked_token: Option<Token>,
        seller_address: address
    }

    struct ChangePriceEvent has drop, store {
        id: TokenId,
        amount: u64,
        listing_id: u64,
        timestamp: u64,
        seller_address: address,
    }

    struct ListedItemsData has key {
        listed_items: Table<TokenId, ListedItem>,
        listing_events: EventHandle<ListEvent>,
        buying_events: EventHandle<BuyEvent>,
        delisting_events: EventHandle<DelistEvent>,
        changing_price_events: EventHandle<ChangePriceEvent>
    }

    // auction mode
    struct AuctionItem has key, store {
        min_selling_price: u64,
        auction_id: u64,
        timestamp: u64,
        duration: u64,
        started_at: u64,
        current_bid: u64,
        current_bidder: address,
        locked_token: Option<Token>,
        owner_token: address
    }

    struct CoinEscrow<phantom CoinType> has key {
        locked_coins: Table<TokenId, Coin<CoinType>>,
    }

    // Set of data sent to the event stream during a auctioning a token
    struct AuctionEvent has store, drop {
        id: TokenId,
        timestamp: u64,
        auction_id: u64,
        min_selling_price: u64,
        duration: u64,
        started_at:u64,
        owner_address: address,
        royalty_payee: address,
        royalty_numerator: u64,
        royalty_denominator: u64
    }

    // Set of data sent to the event stream during a bidding for a token
    struct BidEvent has store, drop {
        id: TokenId,
        auction_id: u64,
        timestamp: u64,
        bid: u64,
        bidder_address: address
    }

    struct AuctionData has key {
        auction_items: Table<TokenId, AuctionItem>,
        auction_events: EventHandle<AuctionEvent>,
        bid_events: EventHandle<BidEvent>,
        claim_coins_events: EventHandle<ClaimCoinsEvent>,
        claim_token_events: EventHandle<ClaimTokenEvent>,
    }

    struct Offerer has store, drop {
        offer_address: address,
        timestamp: u64,
        amount: u64,
        offer_id: u64,
        started_at: u64, // seconds enough
        duration: u64 // seconds enough
    }

    struct ClaimCoinsEvent has store, drop {
        id: TokenId,
        auction_id: u64,
        timestamp: u64,
        owner_token: address
    }

    struct ClaimTokenEvent has store, drop {
        id: TokenId,
        auction_id: u64,
        timestamp: u64,
        bidder_address: address
    }

    // offer mode
    struct OfferItem has key, store {
        offerers: vector<Offerer>,
        token: Option<TokenId>,
        claimable_token_address: address,
        claimable_offer_id: u64,
        accept_address: address
    }

    struct CoinEscrowOffer<phantom CoinType> has key {
        locked_coins: Table<TokenId, Coin<CoinType>>
    }

    struct TokenEscrowOffer has key {
        locked_tokens: Table<TokenId, Token>
    }

    struct OfferEvent has store, drop {
        id: TokenId,
        offer_id: u64,
        timestamp: u64,
        offerer: address,
        amount: u64,
        started_at: u64,
        duration: u64,
        royalty_payee: address,
        royalty_numerator: u64,
        royalty_denominator: u64
    }

    struct AcceptOfferEvent has store, drop {
        id: TokenId,
        offer_id: u64,
        timestamp: u64,
        offerer: address,
        amount: u64,
        owner_token: address
    }

    struct ClaimTokenOffer has store, drop {
        id: TokenId,
        timestamp: u64,
        claimer: address,
    }

    struct CancelOfferEvent has store, drop {
        id: TokenId,
        offer_id: u64,
        timestamp: u64,
        offerer: address
    }

    struct OfferData has key, store {
        offer_items: Table<TokenId, OfferItem>,
        offer_events: EventHandle<OfferEvent>,
        accept_offer_events: EventHandle<AcceptOfferEvent>,
        claim_token_offer_events: EventHandle<ClaimTokenOffer>,
        cancel_offer_events: EventHandle<CancelOfferEvent>
    }

    // publish contract && initial resource
    public entry fun initial_market_script(sender: &signer) {
        let sender_addr = signer::address_of(sender);
        let (market_signer, market_cap) = account::create_resource_account(sender, x"01");
        let market_signer_address = signer::address_of(&market_signer);

        assert!(sender_addr == @lotus, ERROR_INVALID_OWNER);

        if(!exists<TokenCap>(@lotus)){
            move_to(sender, TokenCap {
                cap: market_cap
            })
        };

        if (!exists<MarketData>(market_signer_address)){
            move_to(&market_signer, MarketData {
                fee: 200,
                fund_address: sender_addr
            })
        };

        if (!exists<ListedItemsData>(market_signer_address)) {
            move_to(&market_signer, ListedItemsData {
                listed_items:table::new<TokenId, ListedItem>(),
                listing_events: account::new_event_handle<ListEvent>(&market_signer),
                buying_events: account::new_event_handle<BuyEvent>(&market_signer),
                delisting_events: account::new_event_handle<DelistEvent>(&market_signer),
                changing_price_events: account::new_event_handle<ChangePriceEvent>(&market_signer)
            });
        };

        if (!exists<AuctionData>(market_signer_address)) {
            move_to(&market_signer, AuctionData {
                auction_items: table::new<TokenId, AuctionItem>(),
                auction_events: account::new_event_handle<AuctionEvent>(&market_signer),
                bid_events: account::new_event_handle<BidEvent>(&market_signer),
                claim_coins_events: account::new_event_handle<ClaimCoinsEvent>(&market_signer),
                claim_token_events: account::new_event_handle<ClaimTokenEvent>(&market_signer),
            });
        };

        if (!exists<OfferData>(market_signer_address)){
            move_to(&market_signer, OfferData {
                offer_items: table::new<TokenId,OfferItem>(),
                offer_events: account::new_event_handle(&market_signer),
                accept_offer_events: account::new_event_handle(&market_signer),
                claim_token_offer_events: account::new_event_handle(&market_signer),
                cancel_offer_events: account::new_event_handle(&market_signer)
            })
        }
    }

    fun list_token(
        sender: &signer,
        token_id: TokenId,
        price: u64,
    ) acquires ListedItemsData, TokenCap {
        let sender_addr = signer::address_of(sender);
        let market_cap = &borrow_global<TokenCap>(@lotus).cap;
        let market_signer = &account::create_signer_with_capability(market_cap);
        let market_signer_address = signer::address_of(market_signer);

        let token = token::withdraw_token(sender, token_id, 1);
        let listed_items_data = borrow_global_mut<ListedItemsData>(market_signer_address);
        let listed_items = &mut listed_items_data.listed_items;

        let royalty = token::get_royalty(token_id);
        let royalty_payee = token::get_royalty_payee(&royalty);
        let royalty_numerator = token::get_royalty_numerator(&royalty);
        let royalty_denominator = token::get_royalty_denominator(&royalty);

        // get unique id
        let guid = account::create_guid(market_signer);
        let listing_id = guid::creation_num(&guid);

        event::emit_event<ListEvent>(
            &mut listed_items_data.listing_events,
            ListEvent { 
                id: token_id,
                amount: price,
                seller_address: sender_addr,
                timestamp: timestamp::now_seconds(),
                listing_id,
                royalty_payee,
                royalty_numerator,
                royalty_denominator 
            },
        );

        table::add(listed_items, token_id, ListedItem {
            amount: price,
            listing_id,
            timestamp: timestamp::now_seconds(),
            locked_token: option::some(token),
            seller_address: sender_addr
        })

    }

    // entry batch list script by token owners
    public entry fun batch_list_script(
        sender: &signer,
        creators: vector<address>,
        collection_names: vector<String>,
        token_names: vector<String>,
        property_versions: vector<u64>,
        prices: vector<u64>
    ) acquires ListedItemsData, TokenCap {

        let length_creators = vector::length(&creators);
        let length_collections = vector::length(&collection_names);
        let length_token_names = vector::length(&token_names);
        let length_prices = vector::length(&prices);
        let length_properties = vector::length(&property_versions);

        assert!(length_collections == length_creators
            && length_creators == length_token_names
            && length_token_names == length_prices
            && length_prices == length_properties, ERROR_NOT_ENOUGH_LENGTH);

        let i = length_properties;

        while (i > 0) {
            let creator = vector::pop_back(&mut creators);
            let token_name = vector::pop_back(&mut token_names);
            let collection_name = vector::pop_back(&mut collection_names);
            let price = vector::pop_back(&mut prices);
            let property_version = vector::pop_back(&mut property_versions);

            let token_id = token::create_token_id_raw(creator, collection_name, token_name, property_version);

            list_token(sender, token_id, price);

            i = i - 1;
        }
    }

    // delist token
    fun delist_token(
        sender: &signer,
        token_id: TokenId
    ) acquires ListedItemsData, TokenCap {
        let sender_addr = signer::address_of(sender);
        let market_cap = &borrow_global<TokenCap>(@lotus).cap;
        let market_signer = &account::create_signer_with_capability(market_cap);
        let market_signer_address = signer::address_of(market_signer);

        let listed_items_data = borrow_global_mut<ListedItemsData>(market_signer_address);
        let listed_items = &mut listed_items_data.listed_items;
        let listed_item = table::borrow_mut(listed_items, token_id);

        event::emit_event<DelistEvent>(
            &mut listed_items_data.delisting_events,
            DelistEvent { 
                id: token_id, 
                amount: listed_item.amount,
                listing_id: listed_item.listing_id,
                timestamp: timestamp::now_seconds(),
                seller_address: sender_addr 
            },
        );

        let token = option::extract(&mut listed_item.locked_token);
        token::deposit_token(sender, token);

        let ListedItem {amount: _, timestamp: _, locked_token, seller_address: _, listing_id: _} = table::remove(listed_items, token_id);
        option::destroy_none(locked_token);
    }

    public entry fun batch_delist_script(
        sender: &signer,
        creators: vector<address>,
        collection_names: vector<String>,
        token_names: vector<String>,
        property_versions: vector<u64>
    ) acquires ListedItemsData, TokenCap {

        let length_creators = vector::length(&creators);
        let length_collections = vector::length(&collection_names);
        let length_token_names = vector::length(&token_names);
        let length_properties = vector::length(&property_versions);

        assert!(length_collections == length_creators
            && length_creators == length_token_names
            && length_token_names == length_properties, ERROR_NOT_ENOUGH_LENGTH);

        let i = length_token_names;

        while (i > 0) {
            let creator = vector::pop_back(&mut creators);
            let collection_name = vector::pop_back(&mut collection_names);
            let token_name = vector::pop_back(&mut token_names);
            let property_version = vector::pop_back(&mut property_versions);

            let token_id = token::create_token_id_raw(creator, collection_name, token_name, property_version);
            delist_token(sender, token_id);

            i = i - 1;
        }
    }

    // part of the fixed price sale flow
    fun buy_token<CoinType>(
        sender: &signer, 
        token_id: TokenId,
    ) acquires ListedItemsData, TokenCap, MarketData {
        let sender_addr = signer::address_of(sender);

        let market_cap = &borrow_global<TokenCap>(@lotus).cap;
        let market_signer = &account::create_signer_with_capability(market_cap);
        let market_signer_address = signer::address_of(market_signer);
        let market_data = borrow_global_mut<MarketData>(market_signer_address);

        let listed_items_data = borrow_global_mut<ListedItemsData>(market_signer_address);
        let listed_items = &mut listed_items_data.listed_items;
        let listed_item = table::borrow_mut(listed_items, token_id);
        let seller = listed_item.seller_address;

        assert!(sender_addr != seller, ERROR_INVALID_BUYER);

        let royalty = token::get_royalty(token_id);
        let royalty_payee = token::get_royalty_payee(&royalty);
        let royalty_numerator = token::get_royalty_numerator(&royalty);
        let royalty_denominator = token::get_royalty_denominator(&royalty);

        let _fee_royalty: u64 = 0;

        if (royalty_denominator == 0){
            _fee_royalty = 0;
        } else {
            _fee_royalty = royalty_numerator * listed_item.amount / royalty_denominator;
        };

        let fee_listing = listed_item.amount * market_data.fee / 10000;
        let sub_amount = listed_item.amount - fee_listing - _fee_royalty;

        // print
        // print<u64>(&listed_item.amount);
        // print<u64>(&market_data.fee);
        // print<u64>(&fee_listing);
        // print<u64>(&sub_amount);

        if (_fee_royalty > 0) {
            coin::transfer<CoinType>(sender, royalty_payee, _fee_royalty);
        };

        if (fee_listing > 0) {
            coin::transfer<CoinType>(sender, market_data.fund_address, fee_listing);
        };

        coin::transfer<CoinType>(sender, seller, sub_amount);

        let token = option::extract(&mut listed_item.locked_token);
        token::deposit_token(sender, token);

        event::emit_event<BuyEvent>(
            &mut listed_items_data.buying_events,
            BuyEvent { 
                id: token_id, 
                listing_id: listed_item.listing_id,
                seller_address: listed_item.seller_address,
                timestamp: timestamp::now_seconds(),
                buyer_address: sender_addr 
            },
        );

        let ListedItem {amount: _, timestamp: _, locked_token, seller_address: _, listing_id: _} = table::remove(listed_items, token_id);
        option::destroy_none(locked_token);
    }

    // batch buy script
	public entry fun batch_buy_script(
        sender: &signer,
        creators: vector<address>,
        collection_names: vector<String>,
        token_names: vector<String>,
        property_versions: vector<u64>
    ) acquires ListedItemsData, TokenCap, MarketData {
        let length_creators = vector::length(&creators);
        let length_collections = vector::length(&collection_names);
        let length_token_names = vector::length(&token_names);
        let length_properties = vector::length(&property_versions);

        assert!(length_collections == length_creators
                && length_creators == length_token_names
                && length_token_names == length_properties, ERROR_NOT_ENOUGH_LENGTH);

        let i = length_token_names;

        while (i > 0){
            let creator = vector::pop_back(&mut creators);
            let collection_name = vector::pop_back(&mut collection_names);
            let token_name = vector::pop_back(&mut token_names);
            let property_version = vector::pop_back(&mut property_versions);
            let token_id = token::create_token_id_raw(creator, collection_name, token_name, property_version);

            buy_token<AptosCoin>(sender, token_id);

            i = i - 1;
        }
	}

    // offer mode
    // make offer by listing token (by buyer)
    public entry fun make_offer_script(
        sender: &signer,
        creator: address,
        collection_name: String,
        token_name: String,
        property_version: u64,
        offer_amount: u64,
        duration: u64
    ) acquires TokenCap, OfferData, CoinEscrowOffer {
        let token_id = token::create_token_id_raw(creator, collection_name, token_name, property_version);
        make_offer<AptosCoin>(sender, token_id, offer_amount, duration)
    }

    // make offer for listing token
    fun make_offer<CoinType>(
        sender: &signer,
        token_id: TokenId,
        offer_amount: u64,
        duration: u64
    ) acquires TokenCap, OfferData, CoinEscrowOffer {
        let sender_addr = signer::address_of(sender);
        let market_cap = &borrow_global<TokenCap>(@lotus).cap;
        let market_signer = &account::create_signer_with_capability(market_cap);
        let market_signer_address = signer::address_of(market_signer);

        let offer_data = borrow_global_mut<OfferData>(market_signer_address);
        let offer_items = &mut offer_data.offer_items;
        let is_contain = table::contains(offer_items, token_id);

        let royalty = token::get_royalty(token_id);
        let royalty_payee = token::get_royalty_payee(&royalty);
        let royalty_numerator = token::get_royalty_numerator(&royalty);
        let royalty_denominator = token::get_royalty_denominator(&royalty);

        if(!exists<CoinEscrowOffer<CoinType>>(sender_addr)){
            move_to(sender, CoinEscrowOffer {
                locked_coins: table::new<TokenId, Coin<CoinType>>()
            })
        };

        // unique offer id
        let guid = account::create_guid(market_signer);
        let offer_id = guid::creation_num(&guid);

        let started_at = timestamp::now_seconds();

        if (!is_contain){
            let offerer = Offerer {
                offer_address: sender_addr,
                timestamp: timestamp::now_seconds(),
                amount: offer_amount,
                offer_id,
                started_at,
                duration
            };

            let locked_coins = &mut borrow_global_mut<CoinEscrowOffer<CoinType>>(sender_addr).locked_coins;
            let coins = coin::withdraw<CoinType>(sender, offer_amount);
            table::add(locked_coins, token_id, coins);

            let offerers = vector::empty<Offerer>();

            vector::push_back(&mut offerers, offerer);
            table::add(offer_items, token_id, OfferItem {
                offerers,
                token:option::none<TokenId>(),
                claimable_token_address: @0x0,
                claimable_offer_id: 0,
                accept_address: @0x0
            });

        } else {
            //1. check sender has been offered
            let already_offered = false;
            let index = 0;
            let offer_item = table::borrow_mut(offer_items, token_id);
            let offerers = &mut offer_item.offerers;
            let i = vector::length(offerers);

            while (i > 0){
                let offerer = vector::borrow(offerers, i - 1);
                if (offerer.offer_address == sender_addr) {
                    already_offered = true;
                    index = i - 1;
                    break
                };

                i = i - 1;
            };
            if (already_offered) {
                let locked_coins = &mut borrow_global_mut<CoinEscrowOffer<CoinType>>(sender_addr).locked_coins;
                let coins_refund = table::remove(locked_coins, token_id);
                coin::deposit<CoinType>(sender_addr, coins_refund);
                // locked new amount to offer
                let coins = coin::withdraw<CoinType>(sender, offer_amount);
                table::add(locked_coins, token_id, coins);

                // update offer of sender
                let _offerer = vector::borrow_mut(offerers, index);

                // update offer_id
                offer_id = _offerer.offer_id;

                _offerer.amount = offer_amount;
                _offerer.started_at = started_at;
                _offerer.duration = duration;

            } else {
                //2. locked_coins offered
                let locked_coins = &mut borrow_global_mut<CoinEscrowOffer<CoinType>>(sender_addr).locked_coins;
                let coins = coin::withdraw<CoinType>(sender, offer_amount);
                table::add(locked_coins, token_id, coins);

                //3. add to offerers
                let offerer = Offerer {
                    offer_address: sender_addr,
                    timestamp: timestamp::now_seconds(),
                    amount: offer_amount,
                    offer_id,
                    started_at,
                    duration
                };

                vector::push_back(offerers, offerer);
            }
        };

        event::emit_event(&mut offer_data.offer_events, OfferEvent {
            id: token_id,
            offerer: sender_addr,
            amount: offer_amount,
            timestamp: timestamp::now_seconds(),
            offer_id,
            started_at,
            duration,
            royalty_payee,
            royalty_numerator,
            royalty_denominator 
        })
    }

    // accept offer by token owner.
    public entry fun accept_offer_script(
        sender: &signer,
        creator: address,
        collection_name: String,
        token_name: String,
        property_version: u64,
        offerer: address,
    ) acquires TokenCap, MarketData, OfferData, CoinEscrowOffer, TokenEscrowOffer {
        let token_id = token::create_token_id_raw(creator, collection_name, token_name, property_version);
        accept_offer<AptosCoin>(sender, token_id, offerer)
    }

    fun accept_offer<CoinType>(
        sender: &signer,
        token_id: TokenId,
        offerer: address,
    ) acquires TokenCap, MarketData, OfferData, CoinEscrowOffer, TokenEscrowOffer {
        let sender_addr = signer::address_of(sender);

        if (!exists<TokenEscrowOffer>(sender_addr)){
            move_to(sender, TokenEscrowOffer{
                locked_tokens: table::new<TokenId, Token>()
            })
        };

        let market_cap = &borrow_global<TokenCap>(@lotus).cap;
        let market_signer = &account::create_signer_with_capability(market_cap);
        let market_signer_address = signer::address_of(market_signer);

        let market_data = borrow_global_mut<MarketData>(market_signer_address);
        let offer_data = borrow_global_mut<OfferData>(market_signer_address);
        //
        let offer_items = &mut offer_data.offer_items;

        assert!(table::contains(offer_items, token_id), ERROR);

        let offer_item = table::borrow_mut(offer_items, token_id);
        let offerers = &mut offer_item.offerers;
        //
        let royalty = token::get_royalty(token_id);
        let royalty_payee = token::get_royalty_payee(&royalty);
        let royalty_numerator = token::get_royalty_numerator(&royalty);
        let royalty_denominator = token::get_royalty_denominator(&royalty);

        // check time can accept
        let can_accept = false;
        // check offerer
        let offer_id: u64 = 0;

        let offerers_length = vector::length(offerers);
        while (offerers_length > 0){
            let _offerer = vector::borrow(offerers, offerers_length - 1);
            let time_can_accept = _offerer.duration + _offerer.started_at;

            if(time_can_accept >= timestamp::now_seconds() && _offerer.offer_address == offerer){
                can_accept = true;
                offer_id = _offerer.offer_id;
                break
            };

            offerers_length = offerers_length - 1;
        };

        assert!(can_accept, ERROR_EXPIRED_TIME_ACCEPT);
        //
        let locked_coins = &mut borrow_global_mut<CoinEscrowOffer<CoinType>>(offerer).locked_coins;
        assert!(table::contains(locked_coins, token_id), ERROR_ALREADY_CLAIMED);
        //
        let coins = table::remove(locked_coins, token_id);
        let amount = coin::value(&coins);

        let fee = market_data.fee * amount / 10000;
        let royalty_fee = amount * royalty_numerator / royalty_denominator;

        if (fee > 0) {
            coin::deposit<CoinType>(market_data.fund_address, coin::extract(&mut coins, fee));
        };

        if (royalty_fee > 0) {
            coin::deposit<CoinType>(royalty_payee, coin::extract(&mut coins, royalty_fee));
        };

        coin::deposit<CoinType>(sender_addr, coins);

        // update offer_item
        offer_item.claimable_token_address = offerer;
        offer_item.claimable_offer_id = offer_id;
        option::destroy_none(offer_item.token);
        offer_item.token = some(token_id);
        offer_item.accept_address = sender_addr;

        // lock token offer
        let token = token::withdraw_token(sender, token_id, 1);
        let locked_token_offers = &mut borrow_global_mut<TokenEscrowOffer>(sender_addr).locked_tokens;

        table::add(locked_token_offers, token_id, token);

        event::emit_event(&mut offer_data.accept_offer_events, AcceptOfferEvent {
            id: token_id,
            timestamp: timestamp::now_seconds(),
            offerer,
            offer_id,
            amount,
            owner_token: sender_addr
        })

    }

    // cancel offer by buyer
    public entry fun cancel_offer_script(
        sender: &signer,
        creator: address,
        collection_name: String,
        token_name: String,
        property_version: u64
    ) acquires TokenCap, OfferData, CoinEscrowOffer {
        let token_id = token::create_token_id_raw(creator, collection_name, token_name, property_version);
        cancel_offer<AptosCoin>(sender, token_id)
    }

    fun cancel_offer<CoinType>(
        sender: &signer,
        token_id: TokenId,
    ) acquires TokenCap, OfferData, CoinEscrowOffer {
        let sender_addr = signer::address_of(sender);

        let market_cap = &borrow_global<TokenCap>(@lotus).cap;
        let market_signer = &account::create_signer_with_capability(market_cap);
        let market_signer_address = signer::address_of(market_signer);
        let offer_data = borrow_global_mut<OfferData>(market_signer_address);

        let offer_items = &mut offer_data.offer_items;
        assert!(table::contains(offer_items, token_id), ERROR);

        let offer_item = table::borrow_mut(offer_items, token_id);
        let offerers = &mut offer_item.offerers;

        // remove offer from offerers
        let current_offer_id: u64 = 0;

        let i = vector::length(offerers);
        while (i > 0) {
            let _offerer = vector::borrow_mut(offerers,i - 1);
            if (_offerer.offer_address == sender_addr){
                current_offer_id = _offerer.offer_id;
                vector::remove(offerers, i - 1);
                break
            };

            i = i -1;
        };

        let locked_coins = &mut borrow_global_mut<CoinEscrowOffer<CoinType>>(sender_addr).locked_coins;
        let coins = table::remove(locked_coins, token_id);
        coin::deposit(sender_addr, coins);

        event::emit_event(&mut offer_data.cancel_offer_events, CancelOfferEvent {
            id: token_id,
            offer_id: current_offer_id,
            timestamp: timestamp::now_seconds(),
            offerer: sender_addr
        })
    }

    // claim offer token by buyer(when seller accept offer)
    public entry fun claim_offer_token_script(
        sender: &signer,
        creator: address,
        collection_name: String,
        token_name: String,
        property_version: u64
    ) acquires TokenCap, OfferData, TokenEscrowOffer {
        let token_id = token::create_token_id_raw(creator, collection_name, token_name, property_version);
        claim_offer_token(sender, token_id);
    }

    fun claim_offer_token(
        sender: &signer,
        token_id: TokenId,
    ) acquires TokenCap, OfferData, TokenEscrowOffer {
        let sender_addr = signer::address_of(sender);

        let market_cap = &borrow_global<TokenCap>(@lotus).cap;
        let market_signer = &account::create_signer_with_capability(market_cap);
        let market_signer_address = signer::address_of(market_signer);
        let offer_data = borrow_global_mut<OfferData>(market_signer_address);

        let offer_items = &mut offer_data.offer_items;
        assert!(table::contains(offer_items, token_id), ERROR);

        let offer_item = table::borrow_mut(offer_items, token_id);
        let token_id_claim = option::extract(&mut offer_item.token);

        assert!(offer_item.claimable_token_address == sender_addr, ERROR_NOT_CLAIMABLE);
        assert!(token_id == token_id_claim, ERROR_NOT_CLAIMABLE);

        // claim token
        let locked_token_offers = &mut borrow_global_mut<TokenEscrowOffer>(offer_item.accept_address).locked_tokens;

        assert!(table::contains(locked_token_offers, token_id), ERROR_ALREADY_CLAIMED);

        let token = table::remove(locked_token_offers, token_id);
        token::deposit_token(sender, token);

        event::emit_event(&mut offer_data.claim_token_offer_events, ClaimTokenOffer {
            id: token_id,
            timestamp: timestamp::now_seconds(),
            claimer: sender_addr
        })
    }

    fun initial_auction(
        sender: &signer,
        token_id: TokenId,
        min_selling_price: u64,
        duration: u64,
    ) acquires AuctionData, TokenCap {
        let sender_addr = signer::address_of(sender);

        let started_at = timestamp::now_seconds();
        let token = token::withdraw_token(sender, token_id, 1);

        let market_cap = &borrow_global<TokenCap>(@lotus).cap;
        let market_signer = &account::create_signer_with_capability(market_cap);
        let market_signer_address = signer::address_of(market_signer);

        let auction_data = borrow_global_mut<AuctionData>(market_signer_address);
        let auction_items = &mut auction_data.auction_items;

        // if auction_items still contain token_id, this means that when sender_addr last auctioned this token,
        // they did not claim the coins from the highest bidder
        // sender_addr has received the same token somehow but has not claimed the coins from the initial auction
        assert!(!table::contains(auction_items, token_id), ERROR_CLAIM_COINS_FIRST);

        // create new auction item
        let guid = account::create_guid(market_signer);
        let auction_id = guid::creation_num(&guid);

        let royalty = token::get_royalty(token_id);
        let royalty_payee = token::get_royalty_payee(&royalty);
        let royalty_numerator = token::get_royalty_numerator(&royalty);
        let royalty_denominator = token::get_royalty_denominator(&royalty);

        event::emit_event<AuctionEvent>(
            &mut auction_data.auction_events,
            AuctionEvent { 
                id: token_id, 
                min_selling_price,
                timestamp: timestamp::now_seconds(),
                auction_id,
                started_at, 
                duration,
                owner_address: sender_addr,
                royalty_payee,
                royalty_numerator,
                royalty_denominator
            },
        );

        table::add(auction_items, token_id, AuctionItem {
            min_selling_price,
            duration,
            started_at,
            auction_id,
            current_bid: min_selling_price - 1,
            current_bidder: sender_addr,
            locked_token: some(token),
            owner_token: sender_addr,
            timestamp: timestamp::now_seconds()
        })

    }

    // auction mode
    // inital by token owner
    public entry fun initial_auction_script(
        sender: &signer,
        creator: address,
        collection_name: String,
        token_name: String,
        property_version: u64,
        min_selling_price: u64,
        duration: u64,
    ) acquires AuctionData, TokenCap {
        let token_id = token::create_token_id_raw(creator, collection_name, token_name, property_version);
        initial_auction(sender, token_id, min_selling_price, duration)
    }

    fun is_auction_active(started_at: u64, duration: u64): bool {
        let current_time = timestamp::now_seconds();
        current_time <= started_at + duration && current_time >= started_at
    }

    fun is_auction_complete(started_at: u64, duration: u64): bool {
        let current_time = timestamp::now_seconds();
        current_time > started_at + duration
    }

    fun get_market_signer_address(market_addr: address) : address acquires TokenCap {
        let market_cap = &borrow_global<TokenCap>(market_addr).cap;
        let market_signer = &account::create_signer_with_capability(market_cap);
        let market_signer_address = signer::address_of(market_signer);

        market_signer_address
    }

    // bid by bidder
    public entry fun bid_script(
        sender: &signer,
        creator: address,
        collection_name: String,
        token_name: String,
        property_version: u64,
        bid: u64,
    ) acquires CoinEscrow, AuctionData, TokenCap {
        let token_id = token::create_token_id_raw(creator, collection_name, token_name, property_version);
        bid<AptosCoin>(sender, token_id, bid)
    }

    fun bid<CoinType>(
        sender: &signer,
        token_id: TokenId,
        bid: u64,
    ) acquires CoinEscrow, AuctionData, TokenCap {
        let sender_addr = signer::address_of(sender);
        let market_cap = &borrow_global<TokenCap>(@lotus).cap;
        let market_signer = &account::create_signer_with_capability(market_cap);
        let market_signer_address = signer::address_of(market_signer);

        let auction_data = borrow_global_mut<AuctionData>(market_signer_address);
        let auction_items = &mut auction_data.auction_items;
        let auction_item = table::borrow_mut(auction_items, token_id);
        let seller = auction_item.owner_token;

        assert!(sender_addr != seller, ERROR_INVALID_BUYER);
        assert!(is_auction_active(auction_item.started_at, auction_item.duration), ERROR_AUCTION_INACTIVE);
        assert!(bid > auction_item.current_bid, ERROR_INSUFFICIENT_BID);

        if (!exists<CoinEscrow<CoinType>>(sender_addr)) {
            move_to(sender, CoinEscrow {
                locked_coins: table::new<TokenId, Coin<CoinType>>()
            });
        };

        // refund coin to bidder prev
        if (auction_item.current_bidder != seller) {
            let current_bidder_locked_coins = &mut borrow_global_mut<CoinEscrow<CoinType>>(auction_item.current_bidder).locked_coins;
            let coins = table::remove(current_bidder_locked_coins, token_id);
            coin::deposit<CoinType>(auction_item.current_bidder, coins);
        };

        event::emit_event<BidEvent>(
            &mut auction_data.bid_events,
            BidEvent { 
                id: token_id, 
                auction_id: auction_item.auction_id,
                bid,
                timestamp: timestamp::now_seconds(),
                bidder_address: sender_addr 
            },
        );

        let locked_coins = &mut borrow_global_mut<CoinEscrow<CoinType>>(sender_addr).locked_coins;
        let coins = coin::withdraw<CoinType>(sender, bid);
        table::add(locked_coins, token_id, coins);

        auction_item.current_bidder = sender_addr;
        auction_item.current_bid = bid;
    }

    public entry fun claim_auction_token_script(
        sender: &signer,
        creator: address,
        collection_name: String,
        token_name: String,
        property_version: u64
    ) acquires AuctionData, TokenCap, MarketData, CoinEscrow {
        let token_id = token::create_token_id_raw(creator, collection_name, token_name, property_version);
        claim_auction_token<AptosCoin>(sender, token_id)
    }

    // claim token by buyer
    fun claim_auction_token<CoinType>(
        sender: &signer,
        token_id: TokenId
    ) acquires AuctionData, TokenCap, MarketData, CoinEscrow {
        let sender_addr = signer::address_of(sender);

        let market_cap = &borrow_global<TokenCap>(@lotus).cap;
        let market_signer = &account::create_signer_with_capability(market_cap);
        let market_signer_address = signer::address_of(market_signer);

        let market_data = borrow_global<MarketData>(market_signer_address);
        let auction_data = borrow_global_mut<AuctionData>(market_signer_address);
        let auction_items = &mut auction_data.auction_items;
        let auction_item = table::borrow_mut(auction_items, token_id);

        if (!exists<CoinEscrow<CoinType>>(sender_addr)) {
            move_to(sender, CoinEscrow {
                locked_coins: table::new<TokenId, Coin<CoinType>>()
            });
        };

        assert!(is_auction_complete(auction_item.started_at, auction_item.duration), ERROR_AUCTION_NOT_COMPLETE);
        assert!(sender_addr == auction_item.current_bidder, ERROR_NOT_CLAIMABLE);

        event::emit_event<ClaimTokenEvent>(
            &mut auction_data.claim_token_events,
            ClaimTokenEvent { 
                id: token_id,
                auction_id: auction_item.auction_id,
                timestamp: timestamp::now_seconds(),
                bidder_address: sender_addr 
            },
        );

        let token = option::extract(&mut auction_item.locked_token);
        token::deposit_token(sender, token);

        let royalty = token::get_royalty(token_id);
        let royalty_payee = token::get_royalty_payee(&royalty);
        let royalty_numerator = token::get_royalty_numerator(&royalty);
        let royalty_denominator = token::get_royalty_denominator(&royalty);

        // the auction item can be removed from the auctiondata of the seller once the token and coins are claimed
        let locked_coins = &mut borrow_global_mut<CoinEscrow<CoinType>>(sender_addr).locked_coins;
        // deposit the locked coins to the seller's sender if they have not claimed yet
        if (table::contains(locked_coins, token_id)){
            event::emit_event<ClaimCoinsEvent>(
                &mut auction_data.claim_coins_events,
                ClaimCoinsEvent { 
                    id: token_id, 
                    auction_id: auction_item.auction_id,
                    timestamp: timestamp::now_seconds(),
                    owner_token: auction_item.owner_token 
                },
            );

            let coins = table::remove(locked_coins, token_id);
            let amount = coin::value(&coins);
            let fee = market_data.fee * amount / 10000;
            let royalty_fee = amount * royalty_numerator / royalty_denominator;

            if (fee > 0) {
                coin::deposit(market_data.fund_address, coin::extract(&mut coins, fee));
            };
            
            if (royalty_fee > 0) {
                coin::deposit(royalty_payee, coin::extract(&mut coins, royalty_fee));
            };

            let seller = auction_item.owner_token;
            coin::deposit<CoinType>(seller, coins);
        };

        // remove aution data when token has been claimed
        let AuctionItem { min_selling_price: _, timestamp: _, duration: _, started_at: _, current_bid: _, current_bidder: _, auction_id: _, locked_token, owner_token:_ } = table::remove(auction_items, token_id);
        option::destroy_none(locked_token);
    }

    public entry fun claim_auction_coin_script(
        sender: &signer,
        creator: address,
        collection_name: String,
        token_name: String,
        property_version: u64
    ) acquires CoinEscrow, AuctionData, TokenCap, MarketData {
        let token_id = token::create_token_id_raw(creator, collection_name, token_name, property_version);
        claim_auction_coin<AptosCoin>(sender, token_id)
    }

    // claim coin by token owner
    fun claim_auction_coin<CoinType>(
        sender: &signer,
        token_id: TokenId,
    ) acquires CoinEscrow, AuctionData, TokenCap, MarketData {
        let sender_addr = signer::address_of(sender);
        let market_cap = &borrow_global<TokenCap>(@lotus).cap;
        let market_signer = &account::create_signer_with_capability(market_cap);
        let market_signer_address = signer::address_of(market_signer);

        let market_data = borrow_global<MarketData>(market_signer_address);

        let auction_data = borrow_global_mut<AuctionData>(market_signer_address);
        let auction_items = &mut auction_data.auction_items;

        assert!(table::contains(auction_items, token_id), ERROR_ALREADY_CLAIMED);

        let auction_item = table::borrow(auction_items, token_id);
        assert!(is_auction_complete(auction_item.started_at, auction_item.duration), ERROR_AUCTION_NOT_COMPLETE);
        assert!(sender_addr != auction_item.current_bidder, ERROR_NOT_CLAIMABLE);

        let locked_coins = &mut borrow_global_mut<CoinEscrow<CoinType>>(auction_item.current_bidder).locked_coins;
        assert!(table::contains(locked_coins, token_id), ERROR_ALREADY_CLAIMED);


        let royalty = token::get_royalty(token_id);
        let royalty_payee = token::get_royalty_payee(&royalty);
        let royalty_numerator = token::get_royalty_numerator(&royalty);
        let royalty_denominator = token::get_royalty_denominator(&royalty);

        event::emit_event<ClaimCoinsEvent>(
            &mut auction_data.claim_coins_events,
            ClaimCoinsEvent { 
                auction_id: auction_item.auction_id,
                id: token_id, 
                timestamp: timestamp::now_seconds(),
                owner_token: sender_addr 
            },
        );

        let coins = table::remove(locked_coins, token_id);
        let amount = coin::value(&coins);
        let fee = market_data.fee * amount / 10000;
        let royalty_fee = amount * royalty_numerator / royalty_denominator;

        if (fee > 0 ) {
            coin::deposit(market_data.fund_address, coin::extract(&mut coins,fee));
        };

        if (royalty_fee > 0){
            coin::deposit(royalty_payee,coin::extract(&mut coins,royalty_fee));
        };

        coin::deposit<CoinType>(sender_addr, coins);
    }

    public entry fun change_token_price_script(
        sender: &signer,
        creator: address,
        collection_name: String,
        token_name: String,
        property_vertion: u64,
        new_price: u64,
    ) acquires ListedItemsData, TokenCap {
        let token_id = token::create_token_id_raw(creator, collection_name, token_name, property_vertion);
        change_token_price(sender, token_id, new_price);
    }

    // change token price
    fun change_token_price(
        sender: &signer,
        token_id: TokenId,
        new_price: u64,
    ) acquires ListedItemsData, TokenCap {
        let sender_addr = signer::address_of(sender);
        let market_cap = &borrow_global<TokenCap>(@lotus).cap;
        let market_signer = &account::create_signer_with_capability(market_cap);
        let market_signer_address = signer::address_of(market_signer);

        let listed_items_data = borrow_global_mut<ListedItemsData>(market_signer_address);
        let listed_items = &mut listed_items_data.listed_items;

        assert!(table::contains(listed_items, token_id), ERROR_ALREADY_CLAIMED);

        let listed_item = table::borrow_mut(listed_items, token_id);

        listed_item.amount = new_price;

        event::emit_event(&mut listed_items_data.changing_price_events, ChangePriceEvent {
            id: token_id,
            listing_id: listed_item.listing_id,
            amount: new_price,
            timestamp: timestamp::now_seconds(),
            seller_address: sender_addr
        })
    }

    // TODO's
    // - [x] initial_market
    // - [x] list_token
    // - [x] delist_token
    // - [x] buy_token
    // - [x] make_offer
    // - [x] cancel_offer
    // - [x] accept_offer
    // - [x] claim_offer
    // - [x] initial_auction
    // - [x] bid
    // - [x] claim_auction_token
    // - [x] claim_auction_coin

    #[test(market = @lotus)]
    public fun test_initial_market_script(market: &signer) acquires TokenCap, MarketData {
        // create amount
        account::create_account_for_test(signer::address_of(market));
        // call initial_market_script
        initial_market_script(market);

        // test market data
        let market_addr = signer::address_of(market);
        let market_signer_address = get_market_signer_address(market_addr);
        let market_data = borrow_global_mut<MarketData>(market_signer_address);

        assert!(market_data.fund_address == market_addr, 0);
    }

    #[test(aptos_framework = @0x1, market = @lotus, seller = @0xAE)]
    public fun test_list_token(market: &signer, aptos_framework: &signer, seller: &signer) acquires ListedItemsData, TokenCap {
        // set timestamp
        timestamp::set_time_has_started_for_testing(aptos_framework);
        // create amount
        account::create_account_for_test(signer::address_of(aptos_framework));
        account::create_account_for_test(signer::address_of(market));
        account::create_account_for_test(signer::address_of(seller));

        // initial market
        initial_market_script(market);

        let market_addr = signer::address_of(market);

        let token_id = token::create_collection_and_token(
            seller,
            2,
            2,
            2,
            vector<String>[],
            vector<vector<u8>>[],
            vector<String>[],
            vector<bool>[false, false, false],
            vector<bool>[false, false, false, false, false],
        );

        list_token(seller, token_id, 100);

        let market_signer_address = get_market_signer_address(market_addr);
        let listed_items_data = borrow_global_mut<ListedItemsData>(market_signer_address);
        let listed_items = &mut listed_items_data.listed_items;

        assert!(table::contains(listed_items, token_id), 0);
    }

    #[test(aptos_framework = @0x1, market = @lotus, seller=@0xAF)]
    public fun test_delist_token(market: &signer, aptos_framework: &signer, seller: &signer) acquires ListedItemsData, TokenCap {
        // set timestamp
        timestamp::set_time_has_started_for_testing(aptos_framework);
        // create amount
        account::create_account_for_test(signer::address_of(aptos_framework));
        account::create_account_for_test(signer::address_of(market));
        account::create_account_for_test(signer::address_of(seller));

        // initial market
        initial_market_script(market);

        let market_addr = signer::address_of(market);

        let token_id = token::create_collection_and_token(
            seller,
            2,
            2,
            2,
            vector<String>[],
            vector<vector<u8>>[],
            vector<String>[],
            vector<bool>[false, false, false],
            vector<bool>[false, false, false, false, false],
        );

        list_token(seller, token_id, 100);

        delist_token(seller, token_id);

        let market_signer_address = get_market_signer_address(market_addr);
        let listed_items_data = borrow_global_mut<ListedItemsData>(market_signer_address);
        let listed_items = &mut listed_items_data.listed_items;

        assert!(!table::contains(listed_items, token_id), 0);
    }

    #[test(aptos_framework = @0x1, market = @lotus, seller = @0xAF, buyer = @0xAE)]
    public fun test_buy_token(market: &signer, aptos_framework: &signer, seller: &signer, buyer: &signer) acquires ListedItemsData, TokenCap, MarketData {
        // set timestamp
        timestamp::set_time_has_started_for_testing(aptos_framework);
        // create amount
        account::create_account_for_test(signer::address_of(aptos_framework));
        account::create_account_for_test(signer::address_of(market));
        account::create_account_for_test(signer::address_of(seller));
        account::create_account_for_test(signer::address_of(buyer));

        // initial market
        initial_market_script(market);

        let token_id = token::create_collection_and_token(
            seller,
            2,
            2,
            2,
            vector<String>[],
            vector<vector<u8>>[],
            vector<String>[],
            vector<bool>[false, false, false],
            vector<bool>[false, false, false, false, false],
        );

        list_token(seller, token_id, 300);

        let market_addr = signer::address_of(market);
        let market_signer_address = get_market_signer_address(market_addr);
        let listed_items_data = borrow_global_mut<ListedItemsData>(market_signer_address);
        let listed_items = &mut listed_items_data.listed_items;

        assert!(table::contains(listed_items, token_id), 0);

        coin::create_fake_money(aptos_framework, buyer, 300);
        coin::transfer<coin::FakeMoney>(aptos_framework, signer::address_of(buyer), 300);

        assert!(coin::balance<coin::FakeMoney>(signer::address_of(buyer)) == 300, 1);

        coin::register<coin::FakeMoney>(seller);
        coin::register<coin::FakeMoney>(market);

        buy_token<coin::FakeMoney>(buyer, token_id);

        assert!(coin::balance<coin::FakeMoney>(signer::address_of(market)) == 6, 1);
        assert!(coin::balance<coin::FakeMoney>(signer::address_of(seller)) == 294, 1);
        assert!(coin::balance<coin::FakeMoney>(signer::address_of(buyer)) == 0, 1);
    }

    #[test(aptos_framework = @0x1, market = @lotus, seller = @0xAE)]
    public fun test_change_token_price(market: &signer, aptos_framework: &signer, seller: &signer) acquires ListedItemsData, TokenCap {

        // set timestamp
        timestamp::set_time_has_started_for_testing(aptos_framework);
        // create amount
        account::create_account_for_test(signer::address_of(aptos_framework));
        account::create_account_for_test(signer::address_of(market));
        account::create_account_for_test(signer::address_of(seller));

        // initial market
        initial_market_script(market);

        let token_id = token::create_collection_and_token(
            seller,
            2,
            2,
            2,
            vector<String>[],
            vector<vector<u8>>[],
            vector<String>[],
            vector<bool>[false, false, false],
            vector<bool>[false, false, false, false, false],
        );

        list_token(seller, token_id, 100);
        change_token_price(seller, token_id, 200);

        let market_addr = signer::address_of(market);
        let market_signer_address = get_market_signer_address(market_addr);
        let listed_items_data = borrow_global_mut<ListedItemsData>(market_signer_address);
        let listed_items = &mut listed_items_data.listed_items;
        let listed_item = table::borrow_mut(listed_items, token_id);

        assert!(listed_item.amount == 200, 0);
    }

    // listing with offer mode
    #[test(aptos_framework = @0x1, market = @lotus, seller = @0xAF, buyer = @0xAE)]
    public fun test_make_offer_script(market: &signer, aptos_framework: &signer, seller: &signer, buyer: &signer) acquires ListedItemsData, OfferData, CoinEscrowOffer, TokenCap {
        // set timestamp
        timestamp::set_time_has_started_for_testing(aptos_framework);
        // create amount
        account::create_account_for_test(signer::address_of(aptos_framework));
        account::create_account_for_test(signer::address_of(market));
        account::create_account_for_test(signer::address_of(seller));
        account::create_account_for_test(signer::address_of(buyer));

        // initial market
        initial_market_script(market);

        let token_id = token::create_collection_and_token(
            seller,
            2,
            2,
            2,
            vector<String>[],
            vector<vector<u8>>[],
            vector<String>[],
            vector<bool>[false, false, false],
            vector<bool>[false, false, false, false, false],
        );

        list_token(seller, token_id, 100);

        coin::register<coin::FakeMoney>(seller);
        coin::register<coin::FakeMoney>(market);

        coin::create_fake_money(aptos_framework, buyer, 300);
        coin::transfer<coin::FakeMoney>(aptos_framework, signer::address_of(buyer), 300);

        make_offer<coin::FakeMoney>(buyer, token_id, 50, 120000);

        let market_addr = signer::address_of(market);
        let market_signer_address = get_market_signer_address(market_addr);
        let offer_data = borrow_global_mut<OfferData>(market_signer_address);
        let offer_items = &mut offer_data.offer_items;

        assert!(table::contains(offer_items, token_id), 0);
    }

    #[test(aptos_framework = @0x1, market = @lotus, seller = @0xAF, buyer = @0xAE)]
    public fun test_cancel_offer(market: &signer, aptos_framework: &signer, seller: &signer, buyer: &signer) acquires ListedItemsData, OfferData, CoinEscrowOffer, TokenCap {
        // set timestamp
        timestamp::set_time_has_started_for_testing(aptos_framework);
        // create amount
        account::create_account_for_test(signer::address_of(aptos_framework));
        account::create_account_for_test(signer::address_of(market));
        account::create_account_for_test(signer::address_of(seller));
        account::create_account_for_test(signer::address_of(buyer));

        // initial market
        initial_market_script(market);

        let token_id = token::create_collection_and_token(
            seller,
            2,
            2,
            2,
            vector<String>[],
            vector<vector<u8>>[],
            vector<String>[],
            vector<bool>[false, false, false],
            vector<bool>[false, false, false, false, false],
        );

        list_token(seller, token_id, 100);

        coin::register<coin::FakeMoney>(seller);
        coin::register<coin::FakeMoney>(market);

        coin::create_fake_money(aptos_framework, buyer, 300);
        coin::transfer<coin::FakeMoney>(aptos_framework, signer::address_of(buyer), 300);

        make_offer<coin::FakeMoney>(buyer, token_id, 300, 120000);

        assert!(coin::balance<coin::FakeMoney>(signer::address_of(buyer)) == 0, 1);

        cancel_offer<coin::FakeMoney>(buyer, token_id);
        assert!(coin::balance<coin::FakeMoney>(signer::address_of(buyer)) == 300, 1);
    }
    
    #[test(aptos_framework = @0x1, market = @lotus, seller = @0xAF, buyer1 = @0xAE, buyer2 = @0xAD)]
    public fun test_accept_offer(market: &signer, aptos_framework: &signer, seller: &signer, buyer1: &signer, buyer2: &signer) acquires ListedItemsData, OfferData, CoinEscrowOffer, MarketData, TokenCap, TokenEscrowOffer {
        // set timestamp
        timestamp::set_time_has_started_for_testing(aptos_framework);
        // create amount
        account::create_account_for_test(signer::address_of(aptos_framework));
        account::create_account_for_test(signer::address_of(market));
        account::create_account_for_test(signer::address_of(seller));
        account::create_account_for_test(signer::address_of(buyer1));
        account::create_account_for_test(signer::address_of(buyer2));

        // initial market
        initial_market_script(market);

        let token_id = token::create_collection_and_token(
            seller,
            2,
            2,
            2,
            vector<String>[],
            vector<vector<u8>>[],
            vector<String>[],
            vector<bool>[false, false, false],
            vector<bool>[false, false, false, false, false],
        );

        list_token(seller, token_id, 100);

        coin::register<coin::FakeMoney>(seller);
        coin::register<coin::FakeMoney>(market);
        coin::register<coin::FakeMoney>(buyer2);

        coin::create_fake_money(aptos_framework, buyer1, 500);
        coin::transfer<coin::FakeMoney>(aptos_framework, signer::address_of(buyer1), 300);
        coin::transfer<coin::FakeMoney>(aptos_framework, signer::address_of(buyer2), 200);

        make_offer<coin::FakeMoney>(buyer1, token_id, 300, 120000);
        make_offer<coin::FakeMoney>(buyer2, token_id, 200, 120000);

        assert!(coin::balance<coin::FakeMoney>(signer::address_of(buyer1)) == 0, 1);
        assert!(coin::balance<coin::FakeMoney>(signer::address_of(buyer2)) == 0, 1);

        accept_offer<coin::FakeMoney>(seller, token_id, signer::address_of(buyer1));

        assert!(coin::balance<coin::FakeMoney>(signer::address_of(market)) == 6, 0);
        assert!(coin::balance<coin::FakeMoney>(signer::address_of(seller)) == 294, 0);
    }

    #[test(aptos_framework = @0x1, market = @lotus, seller = @0xAF, buyer = @0xAE)]
    public fun test_claim_offer_token(market: &signer, aptos_framework: &signer, seller: &signer, buyer: &signer) acquires ListedItemsData, OfferData, CoinEscrowOffer, MarketData, TokenCap, TokenEscrowOffer {
        // set timestamp
        timestamp::set_time_has_started_for_testing(aptos_framework);
        // create amount
        account::create_account_for_test(signer::address_of(aptos_framework));
        account::create_account_for_test(signer::address_of(market));
        account::create_account_for_test(signer::address_of(seller));
        account::create_account_for_test(signer::address_of(buyer));

        // initial market
        initial_market_script(market);

        let token_id = token::create_collection_and_token(
            seller,
            2,
            2,
            2,
            vector<String>[],
            vector<vector<u8>>[],
            vector<String>[],
            vector<bool>[false, false, false],
            vector<bool>[false, false, false, false, false],
        );

        list_token(seller, token_id, 100);

        coin::register<coin::FakeMoney>(seller);
        coin::register<coin::FakeMoney>(market);

        coin::create_fake_money(aptos_framework, buyer, 300);
        coin::transfer<coin::FakeMoney>(aptos_framework, signer::address_of(buyer), 300);

        make_offer<coin::FakeMoney>(buyer, token_id, 300, 120000);

        assert!(coin::balance<coin::FakeMoney>(signer::address_of(buyer)) == 0, 1);

        accept_offer<coin::FakeMoney>(seller, token_id, signer::address_of(buyer));

        assert!(coin::balance<coin::FakeMoney>(signer::address_of(market)) == 6, 0);
        assert!(coin::balance<coin::FakeMoney>(signer::address_of(seller)) == 294, 0);

        claim_offer_token(buyer, token_id);

        assert!(token::balance_of(signer::address_of(buyer), token_id) == 1, 0);
    }

    #[test(aptos_framework = @0x1, market = @lotus, seller = @0xAF)]
    public fun test_initial_auction(market: &signer, aptos_framework: &signer, seller: &signer) acquires AuctionData, TokenCap {
        // set timestamp
        timestamp::set_time_has_started_for_testing(aptos_framework);
        // create amount
        account::create_account_for_test(signer::address_of(aptos_framework));
        account::create_account_for_test(signer::address_of(market));
        account::create_account_for_test(signer::address_of(seller));

        // initial market
        initial_market_script(market);

        let token_id = token::create_collection_and_token(
            seller,
            2,
            2,
            2,
            vector<String>[],
            vector<vector<u8>>[],
            vector<String>[],
            vector<bool>[false, false, false],
            vector<bool>[false, false, false, false, false],
        );

        initial_auction(seller, token_id, 100, 120000);

        let market_addr = signer::address_of(market);
        let market_signer_address = get_market_signer_address(market_addr);
        let auction_data = borrow_global_mut<AuctionData>(market_signer_address);
        let auction_items = &mut auction_data.auction_items;

        assert!(table::contains(auction_items, token_id), 0);
    }

    #[test(aptos_framework = @0x1, market = @lotus, seller = @0xAF, bidder1 = @0xAE)]
    public fun test_bid(market: &signer, aptos_framework: &signer, seller: &signer, bidder1: &signer) acquires CoinEscrow, AuctionData, TokenCap {
        // set timestamp
        timestamp::set_time_has_started_for_testing(aptos_framework);
        // create amount
        account::create_account_for_test(signer::address_of(aptos_framework));
        account::create_account_for_test(signer::address_of(market));
        account::create_account_for_test(signer::address_of(seller));
        account::create_account_for_test(signer::address_of(bidder1));
        // account::create_account_for_test(signer::address_of(bidder2));

        // initial market
        initial_market_script(market);

        let token_id = token::create_collection_and_token(
            seller,
            2,
            2,
            2,
            vector<String>[],
            vector<vector<u8>>[],
            vector<String>[],
            vector<bool>[false, false, false],
            vector<bool>[false, false, false, false, false],
        );

        initial_auction(seller, token_id, 100, 120000);

        coin::create_fake_money(aptos_framework, bidder1, 600);
        coin::transfer<coin::FakeMoney>(aptos_framework, signer::address_of(bidder1), 300);

        bid<coin::FakeMoney>(bidder1, token_id, 200);

        let market_addr = signer::address_of(market);
        let market_signer_address = get_market_signer_address(market_addr);
        let auction_data = borrow_global_mut<AuctionData>(market_signer_address);
        let auction_items = &mut auction_data.auction_items;
        let auction_item = table::borrow_mut(auction_items, token_id);

        assert!(auction_item.current_bid == 200, 0);
    }

    #[test(aptos_framework = @0x1, market = @lotus, seller = @0xAF, bidder1 = @0xAE, bidder2 = @0xAD)]
    public fun test_claim_auction_token(market: &signer, aptos_framework: &signer, seller: &signer, bidder1: &signer, bidder2: &signer) acquires CoinEscrow, AuctionData, MarketData, TokenCap {
        // set timestamp
        timestamp::set_time_has_started_for_testing(aptos_framework);
        // create amount
        account::create_account_for_test(signer::address_of(aptos_framework));
        account::create_account_for_test(signer::address_of(market));
        account::create_account_for_test(signer::address_of(seller));
        account::create_account_for_test(signer::address_of(bidder1));
        account::create_account_for_test(signer::address_of(bidder2));

        // initial market
        initial_market_script(market);

        let token_id = token::create_collection_and_token(
            seller,
            2,
            2,
            2,
            vector<String>[],
            vector<vector<u8>>[],
            vector<String>[],
            vector<bool>[false, false, false],
            vector<bool>[false, false, false, false, false],
        );

        // initial auction
        initial_auction(seller, token_id, 100, 120);

        coin::register<coin::FakeMoney>(seller);

        coin::create_fake_money(aptos_framework, bidder1, 600);
        coin::transfer<coin::FakeMoney>(aptos_framework, signer::address_of(bidder1), 300);

        coin::register<coin::FakeMoney>(bidder2);
        coin::register<coin::FakeMoney>(market);

        coin::transfer<coin::FakeMoney>(aptos_framework, signer::address_of(bidder2), 300);

        bid<coin::FakeMoney>(bidder1, token_id, 200);
        bid<coin::FakeMoney>(bidder2, token_id, 250);

        timestamp::update_global_time_for_test(130000*1000);

        claim_auction_token<coin::FakeMoney>(bidder2, token_id);

        assert!(coin::balance<coin::FakeMoney>(signer::address_of(market)) == 5, 1);
        assert!(coin::balance<coin::FakeMoney>(signer::address_of(seller)) == 245, 1);
    }

    #[test(aptos_framework = @0x1, market = @lotus, seller = @0xAF, bidder1 = @0xAE, bidder2 = @0xAD)]
    public fun test_claim_auction_coin(market: &signer, aptos_framework: &signer, seller: &signer, bidder1: &signer, bidder2: &signer) acquires CoinEscrow, AuctionData, MarketData, TokenCap {
                // set timestamp
        timestamp::set_time_has_started_for_testing(aptos_framework);
        // create amount
        account::create_account_for_test(signer::address_of(aptos_framework));
        account::create_account_for_test(signer::address_of(market));
        account::create_account_for_test(signer::address_of(seller));
        account::create_account_for_test(signer::address_of(bidder1));
        account::create_account_for_test(signer::address_of(bidder2));

        // initial market
        initial_market_script(market);

        let token_id = token::create_collection_and_token(
            seller,
            2,
            2,
            2,
            vector<String>[],
            vector<vector<u8>>[],
            vector<String>[],
            vector<bool>[false, false, false],
            vector<bool>[false, false, false, false, false],
        );

        // initial auction
        initial_auction(seller, token_id, 100, 120);

        coin::register<coin::FakeMoney>(seller);

        coin::create_fake_money(aptos_framework, bidder1, 600);
        coin::transfer<coin::FakeMoney>(aptos_framework, signer::address_of(bidder1), 300);

        coin::register<coin::FakeMoney>(bidder2);
        coin::register<coin::FakeMoney>(market);

        coin::transfer<coin::FakeMoney>(aptos_framework, signer::address_of(bidder2), 300);

        bid<coin::FakeMoney>(bidder1, token_id, 200);
        bid<coin::FakeMoney>(bidder2, token_id, 250);

        timestamp::update_global_time_for_test(130000*1000);

        claim_auction_coin<coin::FakeMoney>(seller, token_id);

        assert!(coin::balance<coin::FakeMoney>(signer::address_of(market)) == 5, 1);
        assert!(coin::balance<coin::FakeMoney>(signer::address_of(seller)) == 245, 1);
    }
}