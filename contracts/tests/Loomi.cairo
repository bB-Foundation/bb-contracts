use bb_contracts::Loomi::ILoomiDispatcher;
use bb_contracts::Loomi::ILoomiDispatcherTrait;
use bb_contracts::Loomi::Loomi::{LoomiMinted, MinterApproved};
use bb_contracts::Loomi::Loomi;
use openzeppelin::utils::serde::SerializedAppend;

use openzeppelin_testing::constants::{CALLER, OWNER};
use openzeppelin_token::erc721::interface::{ERC721ABIDispatcher, ERC721ABIDispatcherTrait};
use snforge_std::{
    declare, ContractClassTrait, start_cheat_caller_address, spy_events, EventSpy,
    EventSpyAssertionsTrait, DeclareResultTrait
};
use starknet::{ContractAddress, contract_address_const};

fn USER() -> ContractAddress {
    contract_address_const::<'USER'>()
}

fn USER2() -> ContractAddress {
    contract_address_const::<'USER2'>()
}

fn deploy_loomi() -> ContractAddress {
    let contract = declare("Loomi").unwrap().contract_class();
    let mut calldata = array![];
    calldata.append_serde(OWNER());
    let base_uri: ByteArray = "https://api.example.com/reward/loomi/";
    calldata.append_serde(base_uri);
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    contract_address
}

fn setup_loomi_with_event() -> (EventSpy, ILoomiDispatcher, ContractAddress) {
    let loomi_address = deploy_loomi();

    let spy = spy_events();
    (spy, ILoomiDispatcher { contract_address: loomi_address }, loomi_address)
}

#[test]
fn test_deployment() {
    let loomi_address = deploy_loomi();
    let dispatcher = ERC721ABIDispatcher { contract_address: loomi_address };

    assert(dispatcher.name() == "Loomi", 'Wrong name');
    assert(dispatcher.symbol() == "LOOMI", 'Wrong symbol');
}

#[test]
fn test_minting() {
    let (mut spy, loomi_dispatcher, loomi_address) = setup_loomi_with_event();

    start_cheat_caller_address(loomi_address, OWNER());
    loomi_dispatcher.approve_minter(CALLER());

    let erc721_dispatcher = ERC721ABIDispatcher { contract_address: loomi_address };

    // Start acting as gem contract
    start_cheat_caller_address(loomi_address, CALLER());

    // Mint LOOMI - token ID will be number as u256
    loomi_dispatcher.mint(USER());

    // Сheck LOOMI minted event
    let token_id: u256 = 1;
    let expected_event = Loomi::Event::LoomiMinted(LoomiMinted { user: USER(), token_id });
    spy.assert_emitted(@array![(loomi_address, expected_event)]);

    // Verify ownership
    assert(erc721_dispatcher.owner_of(token_id) == USER(), 'Wrong token owner');
    assert(erc721_dispatcher.balance_of(USER()) == 1, 'Wrong balance');
}

#[test]
#[should_panic(expected: ('Unauthorized minting attempt',))]
fn test_minting_unauthorized_minting() {
    let (_, loomi_dispatcher, loomi_address) = setup_loomi_with_event();

    start_cheat_caller_address(loomi_address, OWNER());
    loomi_dispatcher.approve_minter(CALLER());

    // Start acting as loomi contract
    start_cheat_caller_address(loomi_address, USER());

    // Mint LOOMI - token ID will be number as u256
    loomi_dispatcher.mint(USER());
}

#[test]
fn test_get_tokens_of_owner() {
    let (_, loomi_dispatcher, loomi_address) = setup_loomi_with_event();

    start_cheat_caller_address(loomi_address, OWNER());
    loomi_dispatcher.approve_minter(CALLER());

    let erc721_dispatcher = ERC721ABIDispatcher { contract_address: loomi_address };

    // Start acting as loomi contract
    start_cheat_caller_address(loomi_address, CALLER());

    // Mint LOOMIs
    let token_id_1 = loomi_dispatcher.mint(USER());
    let token_id_2 = loomi_dispatcher.mint(USER2());

    assert(token_id_1 == 1, 'Wrong token id');
    assert(token_id_2 == 2, 'Wrong token id');

    // Verify ownership
    assert(erc721_dispatcher.balance_of(USER()) == 1, 'Wrong balance');
    assert(erc721_dispatcher.balance_of(USER2()) == 1, 'Wrong balance');
    assert_eq!(loomi_dispatcher.get_tokens_of_owner(USER()), array![1]);
    assert_eq!(loomi_dispatcher.get_tokens_of_owner(USER2()), array![2]);
}

#[test]
fn test_approve_minter() {
    let (mut spy, loomi_dispatcher, loomi_address) = setup_loomi_with_event();

    // Start acting as owner
    start_cheat_caller_address(loomi_address, OWNER());

    // Approve minter
    loomi_dispatcher.approve_minter(USER2());

    let expected_event = Loomi::Event::MinterApproved(MinterApproved { minter: USER2() });
    spy.assert_emitted(@array![(loomi_address, expected_event)]);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_approve_only_owner() {
    let (_, loomi_dispatcher, loomi_address) = setup_loomi_with_event();

    start_cheat_caller_address(loomi_address, CALLER());
    loomi_dispatcher.approve_minter(USER());
}

#[test]
#[should_panic(expected: ('Transfer not allowed',))]
fn test_cant_transfer_loomi() {
    let (_, loomi_dispatcher, loomi_address) = setup_loomi_with_event();

    start_cheat_caller_address(loomi_address, OWNER());
    loomi_dispatcher.approve_minter(USER());

    let erc721_dispatcher = ERC721ABIDispatcher { contract_address: loomi_address };

    // Start acting as loomi contract
    start_cheat_caller_address(loomi_address, USER());

    // Mint LOOMI - token ID will be number as u256
    loomi_dispatcher.mint(USER2());

    // Try to transfer to USER2
    start_cheat_caller_address(loomi_address, USER2());
    let token_id: u256 = 1;
    erc721_dispatcher.transfer_from(USER2(), USER(), token_id);
}

#[test]
fn test_name() {
    let loomi_address = deploy_loomi();
    let loomi_dispatcher = ERC721ABIDispatcher { contract_address: loomi_address };

    assert_eq!(loomi_dispatcher.name(), "Loomi");
}

#[test]
fn test_symbol() {
    let loomi_address = deploy_loomi();
    let loomi_dispatcher = ERC721ABIDispatcher { contract_address: loomi_address };

    assert_eq!(loomi_dispatcher.symbol(), "LOOMI");
}

#[test]
fn test_token_uri() {
    let (_, loomi_dispatcher, loomi_address) = setup_loomi_with_event();

    start_cheat_caller_address(loomi_address, OWNER());
    loomi_dispatcher.approve_minter(USER());

    // Start acting as loomi contract
    start_cheat_caller_address(loomi_address, USER());

    // Mint LOOMI - token ID will be number as u256
    loomi_dispatcher.mint(USER2());

    let token_id: u256 = 1;
    assert_eq!(loomi_dispatcher.token_uri(token_id), "https://api.example.com/reward/loomi/1");
}

#[test]
#[should_panic(expected: ('ERC721: invalid token ID',))]
fn test_token_uri_nonexistent() {
    let (_, loomi_dispatcher, loomi_address) = setup_loomi_with_event();

    start_cheat_caller_address(loomi_address, OWNER());
    loomi_dispatcher.approve_minter(USER());

    // Start acting as loomi contract
    start_cheat_caller_address(loomi_address, USER());

    // Mint LOOMI - token ID will be number as u256
    loomi_dispatcher.mint(USER2());

    let invalid_token_id: u256 = 99999;

    // Try to get URI for non-existent token
    loomi_dispatcher.token_uri(invalid_token_id);
}
