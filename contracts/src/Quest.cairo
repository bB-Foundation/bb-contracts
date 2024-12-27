use crate::Quest::Quest::{QuestStatus, QuestType};

#[starknet::interface]
pub trait IQuest<TContractState> {
    fn launch(ref self: TContractState);
    fn join_quest(ref self: TContractState);
    fn leave_quest(ref self: TContractState);
    fn claim_reward(ref self: TContractState, task_id: u256, code: felt252);
    fn add_task(ref self: TContractState, task_id: u256, code_hashes: Array<felt252>);
    fn complete(ref self: TContractState);
    fn cancel(ref self: TContractState);
    fn quest_status(self: @TContractState) -> QuestStatus;
    fn quest_type(self: @TContractState) -> QuestType;
}

#[starknet::contract]
pub mod Quest {
    use core::hash::{HashStateTrait, HashStateExTrait};
    use core::num::traits::Zero;
    use core::poseidon::PoseidonTrait;
    use core::starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, StoragePathEntry, Map
    };
    use core::starknet::{ContractAddress, get_caller_address};
    use crate::Gem::{IGemDispatcher, IGemDispatcherTrait};
    use crate::SBT::{ISBTDispatcher, ISBTDispatcherTrait};
    use openzeppelin::access::ownable::OwnableComponent;
    use super::IQuest;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        gem_contract: ContractAddress,
        sbt_contract: ContractAddress,
        quest_status: QuestStatus,
        quest_type: QuestType,
        participants: Map<ContractAddress, bool>,
        rewarded: Map<ContractAddress, Map<ContractAddress, bool>>,
        // task_id -> (hashed_code -> validity)
        tasks: Map<u256, Map<felt252, bool>>,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        QuestLaunched: QuestLaunched,
        QuestCompleted: QuestCompleted,
        QuestCanceled: QuestCanceled,
        QuestJoined: QuestJoined,
        QuestLeft: QuestLeft,
        TaskAdded: TaskAdded,
        ParticipantRewarded: ParticipantRewarded,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }
    #[derive(Drop, starknet::Event)]
    pub struct QuestLaunched {
        pub quest_status: QuestStatus
    }
    #[derive(Drop, starknet::Event)]
    pub struct QuestCompleted {
        pub quest_status: QuestStatus
    }
    #[derive(Drop, starknet::Event)]
    pub struct QuestCanceled {
        pub quest_status: QuestStatus
    }
    #[derive(Drop, starknet::Event)]
    pub struct QuestJoined {
        pub participant: ContractAddress
    }
    #[derive(Drop, starknet::Event)]
    pub struct QuestLeft {
        pub participant: ContractAddress
    }
    #[derive(Drop, starknet::Event)]
    pub struct TaskAdded {
        pub task_id: u256
    }
    #[derive(Drop, starknet::Event)]
    pub struct ParticipantRewarded {
        pub participant: ContractAddress,
        pub task_id: u256,
        pub token_id: u256
    }

    #[derive(Debug, Copy, Drop, Serde, PartialEq, starknet::Store)]
    pub enum QuestStatus {
        Pending,
        Launched,
        Completed,
        Canceled
    }

    #[derive(Debug, Copy, Drop, Serde, PartialEq, starknet::Store)]
    pub enum QuestType {
        SportsFitness,
        NutritionHealth,
        Arts,
        Education,
        Environment
    }

    pub mod Errors {
        pub const INVALID_ADDRESS: felt252 = 'Invalid address';
        pub const INVALID_STATUS: felt252 = 'Invalid quest status';
        pub const PARTICIPANT_ALREADY_JOINED: felt252 = 'Participant has already joined';
        pub const PARTICIPANT_NOT_JOINED: felt252 = 'Participant has not joined';
        pub const NO_SBT_TOKEN_OWNED: felt252 = 'No SBT token owned by user';
        pub const INVALID_CODE: felt252 = 'Invalid code';
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        gem_contract: ContractAddress,
        sbt_contract: ContractAddress,
        quest_type: QuestType
    ) {
        assert(gem_contract.is_non_zero(), Errors::INVALID_ADDRESS);
        assert(sbt_contract.is_non_zero(), Errors::INVALID_ADDRESS);

        self.ownable.initializer(owner);
        self.gem_contract.write(gem_contract);
        self.sbt_contract.write(sbt_contract);
        self.quest_type.write(quest_type);
        self.quest_status.write(QuestStatus::Pending);
    }

    #[abi(embed_v0)]
    impl Quest of IQuest<ContractState> {
        fn launch(ref self: ContractState) {
            self.ownable.assert_only_owner();

            let quest_status = self.quest_status.read();
            assert(quest_status == QuestStatus::Pending, Errors::INVALID_STATUS);

            self.quest_status.write(QuestStatus::Launched);
            self.emit(QuestLaunched { quest_status: QuestStatus::Launched });
        }

        fn add_task(ref self: ContractState, task_id: u256, code_hashes: Array<felt252>) {
            self.ownable.assert_only_owner();

            let quest_status = self.quest_status.read();
            assert(quest_status == QuestStatus::Pending, Errors::INVALID_STATUS);

            for code_hash in code_hashes {
                self.tasks.entry(task_id).entry(code_hash).write(true);
            };

            self.emit(TaskAdded { task_id });
        }

        fn join_quest(ref self: ContractState) {
            let quest_status = self.quest_status.read();
            assert(quest_status == QuestStatus::Launched, Errors::INVALID_STATUS);

            let caller = get_caller_address();
            let participant = self.participants.entry(caller).read();
            assert(participant == false, Errors::PARTICIPANT_ALREADY_JOINED);

            let sbt_dispatcher = ISBTDispatcher { contract_address: self.sbt_contract.read() };
            assert(sbt_dispatcher.has_token(caller) == true, Errors::NO_SBT_TOKEN_OWNED);

            self.participants.entry(caller).write(true);
            self.emit(QuestJoined { participant: caller });
        }

        fn leave_quest(ref self: ContractState) {
            let quest_status = self.quest_status.read();
            assert(quest_status == QuestStatus::Launched, Errors::INVALID_STATUS);

            let caller = get_caller_address();
            let participant = self.participants.entry(caller).read();
            assert(participant == true, Errors::PARTICIPANT_NOT_JOINED);

            self.participants.entry(caller).write(false);
            self.emit(QuestLeft { participant: caller });
        }

        fn claim_reward(ref self: ContractState, task_id: u256, code: felt252) {
            let quest_status = self.quest_status.read();
            assert(quest_status == QuestStatus::Launched, Errors::INVALID_STATUS);

            let caller = get_caller_address();

            let participant = self.participants.entry(caller).read();
            assert(participant == true, Errors::PARTICIPANT_NOT_JOINED);

            let sbt_dispatcher = ISBTDispatcher { contract_address: self.sbt_contract.read() };
            assert(sbt_dispatcher.has_token(caller) == true, Errors::NO_SBT_TOKEN_OWNED);

            // Validate the provided code against the stored hash
            let hashed_code = PoseidonTrait::new().update_with(code).finalize();
            let is_valid_code = self.tasks.entry(task_id).entry(hashed_code).read();
            assert(is_valid_code == true, Errors::INVALID_CODE);

            let quest_type = self.quest_type.read();
            let quest_type_as_u8 = self._quest_type_as_u8(quest_type);
            let gem_dispatcher = IGemDispatcher { contract_address: self.gem_contract.read() };
            let token_id = gem_dispatcher.mint(caller, quest_type_as_u8);

            self.emit(ParticipantRewarded { participant: caller, task_id, token_id });
        }

        fn complete(ref self: ContractState) {
            self.ownable.assert_only_owner();

            let quest_status = self.quest_status.read();
            assert(quest_status == QuestStatus::Launched, Errors::INVALID_STATUS);

            self.quest_status.write(QuestStatus::Completed);
            self.emit(QuestCompleted { quest_status: QuestStatus::Completed })
        }

        fn cancel(ref self: ContractState) {
            self.ownable.assert_only_owner();

            let quest_status = self.quest_status.read();
            assert(quest_status == QuestStatus::Pending, Errors::INVALID_STATUS);

            self.quest_status.write(QuestStatus::Canceled);
            self.emit(QuestCanceled { quest_status: QuestStatus::Canceled })
        }

        fn quest_status(self: @ContractState) -> QuestStatus {
            self.quest_status.read()
        }

        fn quest_type(self: @ContractState) -> QuestType {
            self.quest_type.read()
        }
    }

    #[generate_trait]
    impl InternalFunctions of InternalFunctionTrait {
        fn _quest_type_as_u8(self: @ContractState, quest_type: QuestType) -> u8 {
            match quest_type {
                QuestType::SportsFitness => 0,
                QuestType::NutritionHealth => 1,
                QuestType::Arts => 2,
                QuestType::Education => 3,
                QuestType::Environment => 4,
            }
        }
    }
}
