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

fn deploy_wardrobe_key() -> ContractAddress {
    let contract = declare("WardrobeKey").unwrap().contract_class();
    let mut calldata = array![];
    calldata.append_serde(OWNER()); // owner address
    let base_uri: ByteArray = "https://api.example.com/token/";
    calldata.append_serde(base_uri); // base_uri
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    contract_address
}

#[test]
fn test_deployment() {
    let contract_address = deploy_wardrobe_key();
    let dispatcher = ERC721ABIDispatcher { contract_address };

    assert(dispatcher.name() == "WardrobeKey", 'Wrong name');
    assert(dispatcher.symbol() == "WKEY", 'Wrong symbol');
}

#[test]
fn test_minting() {
    let contract_address = deploy_wardrobe_key();
    let dispatcher = IWardrobeKeyDispatcher { contract_address };
    let erc721_dispatcher = ERC721ABIDispatcher { contract_address };

    // Start acting as owner
    start_cheat_caller_address(contract_address, OWNER());

    // Mint token ID 1 to USER
    dispatcher.mint(USER());

    // Verify ownership
    assert(erc721_dispatcher.owner_of(1) == USER(), 'Wrong token owner');
    assert(erc721_dispatcher.balance_of(USER()) == 1, 'Wrong balance');

    stop_cheat_caller_address(contract_address);
}

// TODO: enable this test once we have Metamask integration
#[test]
#[ignore]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_mint_not_owner() {
    let contract_address = deploy_wardrobe_key();
    let dispatcher = IWardrobeKeyDispatcher { contract_address };

    // Try to mint as non-owner (default caller)
    start_cheat_caller_address(contract_address, USER());
    dispatcher.mint(USER());
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('Transfer not allowed',))]
fn test_cant_transfer() {
    let contract_address = deploy_wardrobe_key();
    let dispatcher = IWardrobeKeyDispatcher { contract_address };
    let erc721_dispatcher = ERC721ABIDispatcher { contract_address };
    // Start acting as owner
    start_cheat_caller_address(contract_address, OWNER());

    // Mint token ID 1 to USER
    dispatcher.mint(USER());

    // Verify balance
    assert(erc721_dispatcher.balance_of(USER()) == 1, 'Wrong balance');

    // Try to transfer from USER to OWNER
    stop_cheat_caller_address(contract_address);
    start_cheat_caller_address(contract_address, USER());
    erc721_dispatcher.transfer_from(USER(), OWNER(), 1);
}
