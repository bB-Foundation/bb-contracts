use bb_contracts::Gem::IGemDispatcher;
use bb_contracts::Gem::IGemDispatcherTrait;
use bb_contracts::Quest::IQuestDispatcher;
use bb_contracts::Quest::IQuestDispatcherTrait;
use bb_contracts::Quest::Quest::{
    QuestLaunched, QuestCompleted, QuestCanceled, QuestJoined, QuestLeft, ParticipantRewarded,
    TaskAdded
};
use bb_contracts::Quest::Quest;
use bb_contracts::SBT::ISBTDispatcher;
use bb_contracts::SBT::ISBTDispatcherTrait;
use core::hash::{HashStateTrait, HashStateExTrait};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::serde::SerializedAppend;
use openzeppelin_testing::constants::{CALLER, OWNER};

use openzeppelin_testing::{declare_and_deploy};
use snforge_std::{
    declare, ContractClassTrait, start_cheat_caller_address, spy_events, EventSpy, EventSpyTrait,
    EventSpyAssertionsTrait, DeclareResultTrait
};
use starknet::{ContractAddress};

fn QUEST_CALLDATA() -> Span<felt252> {
    let mut calldata = array![];
    calldata.append_serde(Quest::QuestType::SportsFitness);
    calldata.append_serde(CALLER());
    calldata.span()
}

fn deploy_gem(loomi_address: ContractAddress) -> ContractAddress {
    let contract = declare("Gem").unwrap().contract_class();
    let mut calldata = array![];
    calldata.append_serde(OWNER());
    calldata.append_serde(loomi_address);
    let base_uri: ByteArray = "https://api.example.com/reward/gem/";
    calldata.append_serde(base_uri);
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    contract_address
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

fn deploy_sbt() -> ContractAddress {
    let contract = declare("SBT").unwrap().contract_class();
    let mut calldata = array![];
    calldata.append_serde(OWNER());
    let base_uri: ByteArray = "https://api.example.com/sbt/";
    calldata.append_serde(base_uri);
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    contract_address
}

fn setup_quest_with_event() -> (EventSpy, IQuestDispatcher, ContractAddress, ContractAddress) {
    let loomi_address = deploy_loomi();
    let gem_address = deploy_gem(loomi_address);
    let sbt_address = deploy_sbt();

    let mut calldata = array![];
    calldata.append_serde(OWNER());
    calldata.append_serde(gem_address);
    calldata.append_serde(sbt_address);
    calldata.append_serde(Quest::QuestType::SportsFitness);

    let spy = spy_events();
    let quest_address = declare_and_deploy("Quest", calldata);

    start_cheat_caller_address(gem_address, OWNER());
    let gem_dispatcher = IGemDispatcher { contract_address: gem_address };
    gem_dispatcher.approve_minter(quest_address);

    (spy, IQuestDispatcher { contract_address: quest_address }, gem_address, sbt_address)
}

fn setup_quest() -> (EventSpy, IQuestDispatcher, ContractAddress, ContractAddress) {
    let (mut spy, quest, gem_address, sbt_address) = setup_quest_with_event();

    // Drop all events
    let events = spy.get_events().events;
    spy._event_offset += events.len();

    (spy, quest, gem_address, sbt_address)
}

#[test]
fn test_constructor() {
    let (_, quest, _, _) = setup_quest_with_event();

    assert_eq!(quest.quest_status(), Quest::QuestStatus::Pending);
}

#[test]
fn test_launch() {
    let (mut spy, quest, _, _) = setup_quest_with_event();
    let owner = OWNER();

    start_cheat_caller_address(quest.contract_address, owner);

    // Launch the quest
    quest.launch();

    // Сheck launch event
    let expected_event = Quest::Event::QuestLaunched(
        QuestLaunched { quest_status: Quest::QuestStatus::Launched, }
    );
    spy.assert_emitted(@array![(quest.contract_address, expected_event)]);
}

#[test]
#[should_panic(expected: ('Invalid quest status',))]
fn test_launch_invalid_status() {
    let (_, quest, _, _) = setup_quest_with_event();
    let owner = OWNER();

    start_cheat_caller_address(quest.contract_address, owner);

    // Launch the quest
    quest.launch();

    // Launch again
    quest.launch();
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_launch_quest_not_owner() {
    let (_, quest, _, _) = setup_quest_with_event();
    let caller = CALLER();

    start_cheat_caller_address(quest.contract_address, caller);

    // Launch the quest
    quest.launch();
}

#[test]
fn test_join_quest() {
    let (mut spy, quest, _, sbt_address) = setup_quest_with_event();
    let caller = CALLER();

    // Setup caller
    start_cheat_caller_address(sbt_address, caller);
    let sbt_dispatcher = ISBTDispatcher { contract_address: sbt_address };
    sbt_dispatcher.mint();

    // Launch the quest
    start_cheat_caller_address(quest.contract_address, OWNER());
    quest.launch();

    start_cheat_caller_address(quest.contract_address, caller);

    // Join the quest
    quest.join_quest();

    // Check the event for quest joining
    let expected_event = Quest::Event::QuestJoined(QuestJoined { participant: caller, });
    spy.assert_emitted(@array![(quest.contract_address, expected_event)]);
    // TODO: Check caller in participants
}

#[test]
#[should_panic(expected: ('Invalid quest status',))]
fn test_join_quest_invalid_status() {
    let (_, quest, _, _) = setup_quest_with_event();
    let caller = CALLER();

    start_cheat_caller_address(quest.contract_address, caller);

    // Add task
    quest.join_quest();
}

#[test]
#[should_panic(expected: ('Participant has already joined',))]
fn test_join_quest_participant_already_joined() {
    let (_, quest, _, sbt_address) = setup_quest_with_event();
    let caller = CALLER();

    // Setup caller
    start_cheat_caller_address(sbt_address, caller);
    let sbt_dispatcher = ISBTDispatcher { contract_address: sbt_address };
    sbt_dispatcher.mint();

    // Launch the quest
    start_cheat_caller_address(quest.contract_address, OWNER());
    quest.launch();

    start_cheat_caller_address(quest.contract_address, caller);

    // Join the quest
    quest.join_quest();

    // Join the quest again
    quest.join_quest();
}

#[test]
#[should_panic(expected: ('No SBT token owned by user',))]
fn test_join_quest_no_sbt_token_owned() {
    let (_, quest, _, _) = setup_quest_with_event();
    let caller = CALLER();

    // Launch the quest
    start_cheat_caller_address(quest.contract_address, OWNER());
    quest.launch();

    start_cheat_caller_address(quest.contract_address, caller);

    // Join the quest
    quest.join_quest();
}

#[test]
fn test_leave_quest() {
    let (mut spy, quest, _, sbt_address) = setup_quest_with_event();
    let caller = CALLER();

    // Setup caller
    start_cheat_caller_address(sbt_address, caller);
    let sbt_dispatcher = ISBTDispatcher { contract_address: sbt_address };
    sbt_dispatcher.mint();

    // Launch the quest
    start_cheat_caller_address(quest.contract_address, OWNER());
    quest.launch();

    start_cheat_caller_address(quest.contract_address, caller);

    // Join the quest
    quest.join_quest();

    // Leave the quest
    quest.leave_quest();

    // Check the event for quest joining
    let expected_event = Quest::Event::QuestLeft(QuestLeft { participant: caller, });
    spy.assert_emitted(@array![(quest.contract_address, expected_event)]);
    // TODO: Check caller not in participants
}

#[test]
#[should_panic(expected: ('Invalid quest status',))]
fn test_leave_quest_invalid_status() {
    let (_, quest, _, _) = setup_quest_with_event();
    let caller = CALLER();

    start_cheat_caller_address(quest.contract_address, caller);

    // Leave the quest
    quest.leave_quest();
}

#[test]
#[should_panic(expected: ('Participant has not joined',))]
fn test_leave_quest_participant_not_joined() {
    let (_, quest, _, sbt_address) = setup_quest_with_event();
    let caller = CALLER();

    // Setup caller
    start_cheat_caller_address(sbt_address, caller);
    let sbt_dispatcher = ISBTDispatcher { contract_address: sbt_address };
    sbt_dispatcher.mint();

    // Launch the quest
    start_cheat_caller_address(quest.contract_address, OWNER());
    quest.launch();

    start_cheat_caller_address(quest.contract_address, caller);

    // Join the quest
    quest.leave_quest();
}

#[test]
fn test_add_task() {
    let (mut spy, quest, _, _) = setup_quest_with_event();
    let owner = OWNER();

    start_cheat_caller_address(quest.contract_address, owner);

    let task_id = 1;
    let code = 1;
    let hashed_code = PoseidonTrait::new().update_with(code).finalize();

    // Add task
    quest.add_task(task_id, array![hashed_code]);

    // Check the event for quest joining
    let expected_event = Quest::Event::TaskAdded(TaskAdded { task_id: 1, });
    spy.assert_emitted(@array![(quest.contract_address, expected_event)]);
}

#[test]
#[should_panic(expected: ('Invalid quest status',))]
fn test_add_task_invalid_status() {
    let (_, quest, _, _) = setup_quest_with_event();
    let owner = OWNER();

    start_cheat_caller_address(quest.contract_address, owner);

    // Launch the quest
    quest.launch();

    let task_id = 1;
    let code = 1;
    let hashed_code = PoseidonTrait::new().update_with(code).finalize();

    // Add task
    quest.add_task(task_id, array![hashed_code]);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_add_task_not_owner() {
    let (_, quest, _, _) = setup_quest_with_event();
    let caller = CALLER();

    start_cheat_caller_address(quest.contract_address, caller);

    let task_id = 1;
    let code = 1;
    let hashed_code = PoseidonTrait::new().update_with(code).finalize();

    // Add task
    quest.add_task(task_id, array![hashed_code]);
}

#[test]
fn test_claim_reward() {
    let (mut spy, quest, gem_address, sbt_address) = setup_quest_with_event();
    let owner = OWNER();

    start_cheat_caller_address(quest.contract_address, owner);
    let task_id = 1;
    let code = 1;
    let hashed_code = PoseidonTrait::new().update_with(code).finalize();

    // Add task
    quest.add_task(task_id, array![hashed_code]);

    // Launch the quest
    quest.launch();

    // Setup caller
    let caller = CALLER();
    start_cheat_caller_address(sbt_address, caller);
    let sbt_dispatcher = ISBTDispatcher { contract_address: sbt_address };
    sbt_dispatcher.mint();

    start_cheat_caller_address(quest.contract_address, caller);
    // Join the quest
    quest.join_quest();

    start_cheat_caller_address(gem_address, quest.contract_address);
    // Claim reward
    quest.claim_reward(task_id, code);

    // Check the event for participant rewarded
    let expected_event = Quest::Event::ParticipantRewarded(
        ParticipantRewarded { participant: caller, task_id, token_id: 1 }
    );
    spy.assert_emitted(@array![(quest.contract_address, expected_event)]);
}

#[test]
#[should_panic(expected: ('Invalid quest status',))]
fn test_claim_reward_invalid_status() {
    let (_, quest, gem_address, _) = setup_quest_with_event();
    let owner = OWNER();

    start_cheat_caller_address(quest.contract_address, owner);
    let task_id = 1;
    let code = 1;
    let hashed_code = PoseidonTrait::new().update_with(code).finalize();

    // Add task
    quest.add_task(task_id, array![hashed_code]);

    let caller = CALLER();
    start_cheat_caller_address(quest.contract_address, caller);

    // Add task
    quest.join_quest();

    start_cheat_caller_address(gem_address, quest.contract_address);
    // Claim reward
    quest.claim_reward(task_id, code);
}

#[test]
#[should_panic(expected: ('Participant has not joined',))]
fn test_claim_reward_participant_already_joined() {
    let (_, quest, gem_address, _) = setup_quest_with_event();
    let caller = CALLER();

    // Launch the quest
    start_cheat_caller_address(quest.contract_address, OWNER());
    quest.launch();

    start_cheat_caller_address(quest.contract_address, caller);
    start_cheat_caller_address(gem_address, quest.contract_address);

    // Claim reward
    quest.claim_reward(1, 1);
}

#[test]
#[should_panic(expected: ('No SBT token owned by user',))]
fn test_claim_reward_no_sbt_token_owned() {
    let (_, quest, gem_address, _) = setup_quest_with_event();
    let caller = CALLER();

    // Launch the quest
    start_cheat_caller_address(quest.contract_address, OWNER());
    quest.launch();

    start_cheat_caller_address(quest.contract_address, caller);
    // Join the quest
    quest.join_quest();

    start_cheat_caller_address(gem_address, quest.contract_address);
    // Claim reward
    quest.claim_reward(1, 1);
}

#[test]
#[should_panic(expected: ('Unauthorized minting attempt',))]
fn test_claim_reward_unauthorized_minting_attempt() {
    let (_, quest, gem_address, sbt_address) = setup_quest_with_event();

    let owner = OWNER();
    start_cheat_caller_address(quest.contract_address, owner);

    let task_id = 1;
    let code = 1;
    let hashed_code = PoseidonTrait::new().update_with(code).finalize();

    // Add task
    quest.add_task(task_id, array![hashed_code]);

    // Launch the quest
    quest.launch();

    // Setup caller
    let caller = CALLER();
    start_cheat_caller_address(sbt_address, caller);
    let sbt_dispatcher = ISBTDispatcher { contract_address: sbt_address };
    sbt_dispatcher.mint();

    start_cheat_caller_address(quest.contract_address, caller);
    // Join the quest
    quest.join_quest();

    // Unauthorized minter
    start_cheat_caller_address(gem_address, caller);
    // Claim reward
    quest.claim_reward(task_id, code);
}

#[test]
#[should_panic(expected: ('Invalid code',))]
fn test_claim_reward_invalid_code() {
    let (_, quest, gem_address, sbt_address) = setup_quest_with_event();

    let owner = OWNER();

    start_cheat_caller_address(quest.contract_address, owner);

    let task_id = 1;
    let code = 1;
    let hashed_code = PoseidonTrait::new().update_with(code).finalize();
    let owner = OWNER();

    // Add task
    quest.add_task(task_id, array![hashed_code]);

    // Launch the quest
    quest.launch();

    // Setup caller
    let caller = CALLER();
    start_cheat_caller_address(sbt_address, caller);
    let sbt_dispatcher = ISBTDispatcher { contract_address: sbt_address };
    sbt_dispatcher.mint();

    start_cheat_caller_address(quest.contract_address, caller);
    // Join the quest
    quest.join_quest();

    // Unauthorized minter
    start_cheat_caller_address(gem_address, caller);
    // Claim reward
    let invalid_code = 2;
    quest.claim_reward(task_id, invalid_code);
}

#[test]
fn test_complete() {
    let (mut spy, quest, _, _) = setup_quest_with_event();
    let owner = OWNER();

    start_cheat_caller_address(quest.contract_address, owner);

    // Launch the quest
    quest.launch();

    // Complete the quest
    quest.complete();

    // Сheck complete event
    let expected_event = Quest::Event::QuestCompleted(
        QuestCompleted { quest_status: Quest::QuestStatus::Completed, }
    );
    spy.assert_emitted(@array![(quest.contract_address, expected_event)]);
}

#[test]
#[should_panic(expected: ('Invalid quest status',))]
fn test_complete_invalid_status() {
    let (_, quest, _, _) = setup_quest_with_event();
    let owner = OWNER();

    start_cheat_caller_address(quest.contract_address, owner);

    // Launch the quest
    quest.launch();

    // Complete the quest
    quest.complete();

    // Complete again
    quest.complete();
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_complete_quest_not_owner() {
    let (_, quest, _, _) = setup_quest_with_event();
    let caller = CALLER();

    start_cheat_caller_address(quest.contract_address, caller);
    quest.complete();
}

#[test]
fn test_cancel() {
    let (mut spy, quest, _, _) = setup_quest_with_event();
    let owner = OWNER();

    start_cheat_caller_address(quest.contract_address, owner);

    quest.cancel();

    // Сheck cancel event
    let expected_event = Quest::Event::QuestCanceled(
        QuestCanceled { quest_status: Quest::QuestStatus::Canceled, }
    );
    spy.assert_emitted(@array![(quest.contract_address, expected_event)]);
}

#[test]
#[should_panic(expected: ('Invalid quest status',))]
fn test_cancel_invalid_status() {
    let (_, quest, _, _) = setup_quest_with_event();
    let owner = OWNER();

    start_cheat_caller_address(quest.contract_address, owner);

    quest.launch();
    quest.complete();

    // Cancel already completed quest
    quest.cancel();
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_cancel_not_owner() {
    let (_, quest, _, _) = setup_quest_with_event();
    let caller = CALLER();

    start_cheat_caller_address(quest.contract_address, caller);
    quest.cancel();
}

#[test]
fn test_quest_type() {
    let (_, quest, _, _) = setup_quest();

    assert_eq!(quest.quest_type(), Quest::QuestType::SportsFitness);
}

#[test]
fn test_quest_status() {
    let (_, quest, _, _) = setup_quest();

    assert_eq!(quest.quest_status(), Quest::QuestStatus::Pending);
}
