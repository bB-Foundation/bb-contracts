use bb_contracts::BBAvatar::{IBBAvatarDispatcher, IBBAvatarDispatcherTrait, AccessoryInfo};
use bb_contracts::WardrobeKey::{IWardrobeKeyDispatcher, IWardrobeKeyDispatcherTrait};
use openzeppelin_token::erc721::interface::{ERC721ABIDispatcher, ERC721ABIDispatcherTrait};
use openzeppelin_utils::serde::SerializedAppend;
use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address,
    stop_cheat_caller_address
};
use starknet::{ContractAddress, contract_address_const};

fn OWNER() -> ContractAddress {
    contract_address_const::<'OWNER'>()
}

fn USER() -> ContractAddress {
    contract_address_const::<'USER'>()
}

fn USER2() -> ContractAddress {
    contract_address_const::<'USER2'>()
}

fn deploy_avatar() -> ContractAddress {
    let contract = declare("BBAvatar").unwrap().contract_class();
    let mut calldata = array![];
    calldata.append_serde(OWNER()); // owner address
    let base_uri: ByteArray = "https://api.example.com/avatar/";
    calldata.append_serde(base_uri); // base_uri
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    contract_address
}

fn deploy_wardrobe_key() -> ContractAddress {
    let contract = declare("WardrobeKey").unwrap().contract_class();
    let mut calldata = array![];
    calldata.append_serde(OWNER()); // owner address
    let base_uri: ByteArray = "https://api.example.com/key/";
    calldata.append_serde(base_uri); // base_uri
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    contract_address
}

#[test]
fn test_deployment() {
    let contract_address = deploy_avatar();
    let dispatcher = ERC721ABIDispatcher { contract_address };

    assert(dispatcher.name() == "BBAvatar", 'Wrong name');
    assert(dispatcher.symbol() == "BBAV", 'Wrong symbol');
}

#[test]
fn test_minting() {
    let contract_address = deploy_avatar();
    let dispatcher = IBBAvatarDispatcher { contract_address };
    let erc721_dispatcher = ERC721ABIDispatcher { contract_address };

    // Start acting as USER
    start_cheat_caller_address(contract_address, USER());

    // Mint avatar - token ID will be USER's address as felt252
    dispatcher.mint();

    // Convert USER address to felt252 for token_id
    let user_felt: felt252 = USER().into();
    let token_id: u256 = user_felt.into();

    // Verify ownership
    assert(erc721_dispatcher.owner_of(token_id) == USER(), 'Wrong token owner');
    assert(erc721_dispatcher.balance_of(USER()) == 1, 'Wrong balance');

    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_accessory_management() {
    // Deploy contracts
    let avatar_address = deploy_avatar();
    let key_address = deploy_wardrobe_key();

    let avatar = IBBAvatarDispatcher { contract_address: avatar_address };
    let key = IWardrobeKeyDispatcher { contract_address: key_address };

    // Register affiliate (wardrobe key contract)
    start_cheat_caller_address(avatar_address, OWNER());
    let affiliate_id: felt252 = 'test_affiliate';
    avatar.register_affiliate(affiliate_id, key_address);
    stop_cheat_caller_address(avatar_address);

    // Mint key to USER
    start_cheat_caller_address(key_address, OWNER());
    key.mint(USER());
    stop_cheat_caller_address(key_address);

    // USER mints avatar and tries to equip accessory
    start_cheat_caller_address(avatar_address, USER());
    avatar.mint();

    let user_felt: felt252 = USER().into();
    let token_id: u256 = user_felt.into();

    let accessory_id: felt252 = 'test_hat';
    let accessory = AccessoryInfo {
        affiliate_id: affiliate_id, accessory_id: accessory_id, is_on: true
    };

    let mut accessories = array![accessory];
    avatar.update_accessories(accessories.span());

    // Verify accessory is equipped
    assert(avatar.has_accessory(token_id, affiliate_id, accessory_id), 'Accessory not equipped');

    stop_cheat_caller_address(avatar_address);
}

#[test]
#[should_panic(expected: ('Transfer not allowed',))]
fn test_cant_transfer_avatar() {
    let avatar_address = deploy_avatar();
    let avatar = IBBAvatarDispatcher { contract_address: avatar_address };
    let erc721_dispatcher = ERC721ABIDispatcher { contract_address: avatar_address };

    // USER mints avatar
    start_cheat_caller_address(avatar_address, USER());
    avatar.mint();

    let user_felt: felt252 = USER().into();
    let token_id: u256 = user_felt.into();

    // Try to transfer to USER2
    erc721_dispatcher.transfer_from(USER(), USER2(), token_id);
}

#[test]
#[should_panic(expected: ('Caller already has a token',))]
fn test_cant_mint_twice() {
    let avatar_address = deploy_avatar();
    let avatar = IBBAvatarDispatcher { contract_address: avatar_address };

    // USER mints avatar
    start_cheat_caller_address(avatar_address, USER());
    avatar.mint();

    // USER mints avatar again
    avatar.mint();
}

#[test]
fn test_token_uri_generation() {
    let avatar_address = deploy_avatar();
    let key1_address = deploy_wardrobe_key();
    let key2_address = deploy_wardrobe_key();
    let key3_address = deploy_wardrobe_key();

    let avatar = IBBAvatarDispatcher { contract_address: avatar_address };
    let key1 = IWardrobeKeyDispatcher { contract_address: key1_address };
    let key2 = IWardrobeKeyDispatcher { contract_address: key2_address };
    let key3 = IWardrobeKeyDispatcher { contract_address: key3_address };

    // Register two affiliates
    start_cheat_caller_address(avatar_address, OWNER());
    let affiliate1: felt252 = 'bored_apes';
    let affiliate2: felt252 = 'oxford';
    let affiliate3: felt252 = 'punk_wear';
    avatar.register_affiliate(affiliate1, key1_address);
    avatar.register_affiliate(affiliate2, key2_address);
    avatar.register_affiliate(affiliate3, key3_address);
    // Register accessories
    avatar.register_accessory(affiliate1, 'hat');
    avatar.register_accessory(affiliate1, 't-shirt');
    avatar.register_accessory(affiliate1, 'other');
    avatar.register_accessory(affiliate2, 'glasses');
    avatar.register_accessory(affiliate3, 'other');
    stop_cheat_caller_address(avatar_address);

    // Mint keys to USER
    start_cheat_caller_address(key1_address, OWNER());
    key1.mint(USER());
    stop_cheat_caller_address(key1_address);

    start_cheat_caller_address(key2_address, OWNER());
    key2.mint(USER());
    stop_cheat_caller_address(key2_address);

    start_cheat_caller_address(key3_address, OWNER());
    key3.mint(USER());
    stop_cheat_caller_address(key3_address);

    // USER mints avatar and equips accessories
    start_cheat_caller_address(avatar_address, USER());
    // No need to mint, as it's done automatically if there's no token
    // avatar.mint();

    let user_felt: felt252 = USER().into();
    let token_id: u256 = user_felt.into();

    // Create accessories list with items from both affiliates
    let accessory1 = AccessoryInfo { affiliate_id: affiliate1, accessory_id: 'hat', is_on: true };
    let accessory2 = AccessoryInfo {
        affiliate_id: affiliate1, accessory_id: 't-shirt', is_on: true
    };
    let accessory3 = AccessoryInfo {
        affiliate_id: affiliate2, accessory_id: 'glasses', is_on: true
    };

    let mut accessories = array![accessory1, accessory2, accessory3];
    avatar.update_accessories(accessories.span());

    // Get and verify token URI
    let token_uri = avatar.token_uri(token_id);

    // The URI should contain base_uri + all equipped accessories in order
    // Expected format: https://api.example.com/avatar/?bored_apes=hat,t-shirt&oxford=glasses
    // But it won't work because felts will are formatted as numbers
    let expected_uri: ByteArray =
        "https://api.example.com/avatar/?464847747018460782159219=6840692,32701070994666100&122562905338468=29111088405767539";
    println!("Expected URI: {}", expected_uri);
    println!("Generated URI: {}", token_uri);
    assert(token_uri == expected_uri, 'Wrong token URI generated');

    stop_cheat_caller_address(avatar_address);
}

#[test]
#[should_panic(expected: ('ERC721: invalid token ID',))]
fn test_token_uri_nonexistent() {
    let avatar_address = deploy_avatar();
    let avatar = IBBAvatarDispatcher { contract_address: avatar_address };

    // Try to get URI for non-existent token
    avatar.token_uri(99999.into());
}

// TODO: enable this once we have everything integrated
#[test]
#[ignore]
#[should_panic(expected: ('Caller does not have the key',))]
fn test_cant_equip_without_key() {
    let avatar_address = deploy_avatar();
    let key_address = deploy_wardrobe_key();

    let avatar = IBBAvatarDispatcher { contract_address: avatar_address };

    // Register affiliate
    start_cheat_caller_address(avatar_address, OWNER());
    let affiliate_id: felt252 = 'test_affiliate';
    avatar.register_affiliate(affiliate_id, key_address);
    stop_cheat_caller_address(avatar_address);

    // USER mints avatar but doesn't have the key
    start_cheat_caller_address(avatar_address, USER());
    avatar.mint();

    // Try to equip accessory without having the key
    let accessory = AccessoryInfo {
        affiliate_id: affiliate_id, accessory_id: 'test_hat', is_on: true
    };
    let mut accessories = array![accessory];
    avatar.update_accessories(accessories.span());
}

#[test]
#[should_panic(expected: ('Affiliate key not registered',))]
fn test_cant_equip_unregistered_affiliate() {
    let avatar_address = deploy_avatar();
    let avatar = IBBAvatarDispatcher { contract_address: avatar_address };

    // USER mints avatar
    start_cheat_caller_address(avatar_address, USER());
    avatar.mint();

    // Try to equip accessory from unregistered affiliate
    let accessory = AccessoryInfo {
        affiliate_id: 'nonexistent_affiliate', accessory_id: 'test_hat', is_on: true
    };
    let mut accessories = array![accessory];
    avatar.update_accessories(accessories.span());
}

#[test]
fn test_get_accessories_for_affiliate() {
    let avatar_address = deploy_avatar();
    let avatar = IBBAvatarDispatcher { contract_address: avatar_address };

    // Register affiliate and accessories as OWNER
    start_cheat_caller_address(avatar_address, OWNER());

    let affiliate_id: felt252 = 'test_affiliate';
    let key_address = deploy_wardrobe_key();
    avatar.register_affiliate(affiliate_id, key_address);

    // Register multiple accessories
    let accessory1: felt252 = 'hat';
    let accessory2: felt252 = 'glasses';
    let accessory3: felt252 = 'shirt';

    avatar.register_accessory(affiliate_id, accessory1);
    avatar.register_accessory(affiliate_id, accessory2);
    avatar.register_accessory(affiliate_id, accessory3);

    // Get registered accessories
    let accessories = avatar.get_accessories_for_affiliate(affiliate_id);

    // Verify accessories list
    assert(*accessories.at(0) == accessory1, 'Wrong first accessory');
    assert(*accessories.at(1) == accessory2, 'Wrong second accessory');
    assert(*accessories.at(2) == accessory3, 'Wrong third accessory');
    assert(accessories.len() == 3, 'Wrong number of accessories');

    stop_cheat_caller_address(avatar_address);
}

#[test]
fn test_get_affiliates() {
    let avatar_address = deploy_avatar();
    let avatar = IBBAvatarDispatcher { contract_address: avatar_address };

    // Register multiple affiliates as OWNER
    start_cheat_caller_address(avatar_address, OWNER());

    // Create multiple wardrobe key contracts
    let key1_address = deploy_wardrobe_key();
    let key2_address = deploy_wardrobe_key();
    let key3_address = deploy_wardrobe_key();

    // Register affiliates
    let affiliate1: felt252 = 'bored_apes';
    let affiliate2: felt252 = 'oxford';
    let affiliate3: felt252 = 'punk_wear';

    avatar.register_affiliate(affiliate1, key1_address);
    avatar.register_affiliate(affiliate2, key2_address);
    avatar.register_affiliate(affiliate3, key3_address);

    // Get registered affiliates
    let affiliates = avatar.get_affiliates();

    // Verify affiliates list
    assert(*affiliates.at(0) == affiliate1, 'Wrong first affiliate');
    assert(*affiliates.at(1) == affiliate2, 'Wrong second affiliate');
    assert(*affiliates.at(2) == affiliate3, 'Wrong third affiliate');
    assert(affiliates.len() == 3, 'Wrong number of affiliates');

    stop_cheat_caller_address(avatar_address);
}
