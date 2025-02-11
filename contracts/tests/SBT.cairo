use bb_contracts::SBT::ISBTDispatcher;
use bb_contracts::SBT::ISBTDispatcherTrait;
use bb_contracts::SBT::SBT::{Team, SBTMinted};
use bb_contracts::SBT::SBT;
use openzeppelin::utils::serde::SerializedAppend;

use openzeppelin_testing::constants::{OWNER};
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

fn deploy_sbt() -> ContractAddress {
    let contract = declare("SBT").unwrap().contract_class();
    let mut calldata = array![];
    calldata.append_serde(OWNER());
    let base_uri: ByteArray = "https://api.example.com/reward/gem/";
    calldata.append_serde(base_uri);
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    contract_address
}

fn setup_sbt_with_event() -> (EventSpy, ISBTDispatcher, ContractAddress) {
    let sbt_address = deploy_sbt();

    let spy = spy_events();
    (spy, ISBTDispatcher { contract_address: sbt_address }, sbt_address)
}

#[test]
fn test_deployment() {
    let contract_address = deploy_sbt();
    let dispatcher = ERC721ABIDispatcher { contract_address };

    assert(dispatcher.name() == "SBT", 'Wrong name');
    assert(dispatcher.symbol() == "SBT", 'Wrong symbol');
}

#[test]
fn test_minting() {
    let (mut spy, sbt_dispatcher, sbt_address) = setup_sbt_with_event();

    let erc721_dispatcher = ERC721ABIDispatcher { contract_address: sbt_address };

    // Start acting as SBT contract
    start_cheat_caller_address(sbt_address, USER());

    // Mint SBT - token ID will be USER's address as felt252
    sbt_dispatcher.mint();

    let user_felt: felt252 = USER().into();
    let token_id: u256 = user_felt.into();

    // Сheck SBT minted event
    let expected_event = SBT::Event::SBTMinted(
        SBTMinted { user: USER(), token_id, team: Team::BlueFox }
    );

    spy.assert_emitted(@array![(sbt_address, expected_event)]);

    // Verify ownership
    assert(erc721_dispatcher.owner_of(token_id) == USER(), 'Wrong token owner');
    assert(erc721_dispatcher.balance_of(USER()) == 1, 'Wrong balance');
}

#[test]
#[should_panic(expected: ('Token already owned by caller',))]
fn test_minting_token_already_owned() {
    let (_, sbt_dispatcher, sbt_address) = setup_sbt_with_event();

    // Start acting as SBT contract
    start_cheat_caller_address(sbt_address, USER());

    // Mint SBT - token ID will be USER's address as felt252
    sbt_dispatcher.mint();

    // Mint again
    sbt_dispatcher.mint();
}

#[test]
#[should_panic(expected: ('Transfer not allowed',))]
fn test_cant_transfer_sbt() {
    let (_, sbt_dispatcher, sbt_address) = setup_sbt_with_event();

    let erc721_dispatcher = ERC721ABIDispatcher { contract_address: sbt_address };

    // Start acting as user
    start_cheat_caller_address(sbt_address, USER());

    // Mint SBT - token ID will be USER's address as felt252
    sbt_dispatcher.mint();

    // Try to transfer to USER2
    let user_felt: felt252 = USER().into();
    let token_id: u256 = user_felt.into();
    erc721_dispatcher.transfer_from(USER(), USER2(), token_id);
}

#[test]
fn test_get_user_team() {
    let (_, sbt_dispatcher, sbt_address) = setup_sbt_with_event();

    // Start acting as user
    start_cheat_caller_address(sbt_address, USER());

    // Mint SBT - token ID will be USER's address as felt252
    sbt_dispatcher.mint();

    // Start acting as user 2
    start_cheat_caller_address(sbt_address, USER2());
    // Get user team
    let team = sbt_dispatcher.get_user_team(USER());

    assert_eq!(team, Team::BlueFox);
    match team {
        Team::BlueFox | Team::RedWolf | Team::GreenApple => { // Team is valid, no action needed
        },
        _ => panic!("Invalid team returned"),
    }
}

#[test]
fn test_has_token() {
    let (_, sbt_dispatcher, sbt_address) = setup_sbt_with_event();

    // Start acting as user
    start_cheat_caller_address(sbt_address, USER());

    // Mint SBT - token ID will be USER's address as felt252
    sbt_dispatcher.mint();
    //assert(sbt_dispatcher.has_token(USER()), true)
}

#[test]
fn test_name() {
    let contract_address = deploy_sbt();
    let gem_dispatcher = ERC721ABIDispatcher { contract_address };

    assert_eq!(gem_dispatcher.name(), "SBT");
}

#[test]
fn test_symbol() {
    let contract_address = deploy_sbt();
    let gem_dispatcher = ERC721ABIDispatcher { contract_address };

    assert_eq!(gem_dispatcher.symbol(), "SBT");
}

#[test]
fn test_token_uri() {
    let (_, sbt_dispatcher, sbt_address) = setup_sbt_with_event();

    // Start acting as user
    start_cheat_caller_address(sbt_address, USER());

    // Mint SBT - token ID will be USER's address as felt252
    sbt_dispatcher.mint();

    let user_felt: felt252 = USER().into();
    let token_id: u256 = user_felt.into();

    let expected_uri = format!("https://api.example.com/reward/gem/{}", token_id);
    assert_eq!(sbt_dispatcher.token_uri(token_id), expected_uri);
}

#[test]
#[should_panic(expected: ('ERC721: invalid token ID',))]
fn test_token_uri_nonexistent() {
    let (_, sbt_dispatcher, sbt_address) = setup_sbt_with_event();

    // Start acting as user
    start_cheat_caller_address(sbt_address, USER());

    // Mint GEM - token ID will be number as u256 and color GemColor::Blue
    sbt_dispatcher.mint();

    let invalid_token_id: u256 = 99999;

    // Try to get URI for non-existent token
    sbt_dispatcher.token_uri(invalid_token_id);
}
