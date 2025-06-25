/// Each turn, a player repeatedly rolls a die until a 1 is rolled or the player decides to "hold":
///
/// If the player rolls a 1, they score nothing and it becomes the next player's turn.
/// If the player rolls any other number, it is added to their turn total and the player's turn continues.
/// If a player chooses to "hold", their turn total is added to their score, and it becomes the next player's turn.
/// The first player to score 100 or more points wins.
///
/// Your task:
/// - Implement the pig game here
/// - Integrate it with the pig master contract
/// - Test it with the frontend
module pig_game_addr::pig_game {

    use std::signer;
    use aptos_framework::randomness;
    use aptos_std::smart_table;
    use aptos_std::smart_table::SmartTable;
    use pig_master_addr::pig_master;

    /// Function is not implemented
    const E_NOT_IMPLEMENTED: u64 = 1;
    /// Game is already over
    const E_GAME_OVER: u64 = 2;
    /// No active game found
    const E_NO_ACTIVE_GAME: u64 = 3;

    /// Game state for a single user
    struct UserGameState has store, drop {
        last_roll: u8,
        turn_score: u64,
        total_score: u64,
        round: u64,
        turn: u64,
        game_over: bool,
    }

    /// Global state to track all user games
    struct GlobalGameState has key {
        user_games: SmartTable<address, UserGameState>,
        total_games_played: u64,
    }

    /// Initialize the global game state
    fun init_module(deployer: &signer) {
        let global_state = GlobalGameState {
            user_games: smart_table::new<address, UserGameState>(),
            total_games_played: 0,
        };
        move_to(deployer, global_state);
    }

    #[test_only]
    /// Initialize for testing
    public fun init_for_test(deployer: &signer) {
        let global_state = GlobalGameState {
            user_games: smart_table::new<address, UserGameState>(),
            total_games_played: 0,
        };
        move_to(deployer, global_state);
    }

    #[test_only]
    /// Test wrapper for hold
    public fun hold_for_test(user: &signer) acquires GlobalGameState {
        hold(user);
    }

    #[test_only]
    /// Test wrapper for complete_game
    public fun complete_game_for_test(user: &signer) acquires GlobalGameState {
        complete_game(user);
    }

    #[test_only]
    /// Test wrapper for reset_game
    public fun reset_game_for_test(user: &signer) acquires GlobalGameState {
        reset_game(user);
    }

    // ======================== Entry (Write) functions ========================
    #[randomness]
    /// Roll the dice
    entry fun roll_dice(user: &signer) acquires GlobalGameState {
        let user_address = signer::address_of(user);
        let global_state = borrow_global_mut<GlobalGameState>(@pig_game_addr);
        
        // Initialize user game if not exists
        if (!smart_table::contains(&global_state.user_games, user_address)) {
            smart_table::add(&mut global_state.user_games, user_address, UserGameState {
                last_roll: 0,
                turn_score: 0,
                total_score: 0,
                round: 0,
                turn: 0,
                game_over: false,
            });
        };
        
        let user_game = smart_table::borrow_mut(&mut global_state.user_games, user_address);
        assert!(!user_game.game_over, E_GAME_OVER);
        
        // Generate random number 1-6
        let dice_roll = ((randomness::u64_integer() % 6) + 1) as u8;
        user_game.last_roll = dice_roll;
        user_game.round = user_game.round + 1;
        
        if (dice_roll == 1) {
            // Turn ends, reset turn score
            user_game.turn_score = 0;
            user_game.turn = user_game.turn + 1;
        } else {
            // Add to turn score
            user_game.turn_score = user_game.turn_score + (dice_roll as u64);
        };
    }

    #[test_only]
    /// Optional, useful for testing purposes
    public fun roll_dice_for_test(user: &signer, num: u8) acquires GlobalGameState {
        let user_address = signer::address_of(user);
        let global_state = borrow_global_mut<GlobalGameState>(@pig_game_addr);
        
        // Initialize user game if not exists
        if (!smart_table::contains(&global_state.user_games, user_address)) {
            smart_table::add(&mut global_state.user_games, user_address, UserGameState {
                last_roll: 0,
                turn_score: 0,
                total_score: 0,
                round: 0,
                turn: 0,
                game_over: false,
            });
        };
        
        let user_game = smart_table::borrow_mut(&mut global_state.user_games, user_address);
        assert!(!user_game.game_over, E_GAME_OVER);
        
        user_game.last_roll = num;
        user_game.round = user_game.round + 1;
        
        if (num == 1) {
            // Turn ends, reset turn score
            user_game.turn_score = 0;
            user_game.turn = user_game.turn + 1;
        } else {
            // Add to turn score
            user_game.turn_score = user_game.turn_score + (num as u64);
        };
    }

    /// End the turn by calling hold, add points to the overall
    /// accumulated score for the current game for the specified user
    entry fun hold(user: &signer) acquires GlobalGameState {
        let user_address = signer::address_of(user);
        let global_state = borrow_global_mut<GlobalGameState>(@pig_game_addr);
        
        assert!(smart_table::contains(&global_state.user_games, user_address), E_NO_ACTIVE_GAME);
        let user_game = smart_table::borrow_mut(&mut global_state.user_games, user_address);
        assert!(!user_game.game_over, E_GAME_OVER);
        
        // Add turn score to total score
        user_game.total_score = user_game.total_score + user_game.turn_score;
        user_game.turn_score = 0;
        user_game.last_roll = 0; // Reset last roll on hold
        user_game.turn = user_game.turn + 1;
        
        // Check if game is won
        if (user_game.total_score >= pig_master::points_to_win()) {
            user_game.game_over = true;
        };
    }

    /// The intended score has been reached, end the game, publish the
    /// score to both the global storage
    entry fun complete_game(user: &signer) acquires GlobalGameState {
        let user_address = signer::address_of(user);
        let global_state = borrow_global_mut<GlobalGameState>(@pig_game_addr);
        
        assert!(smart_table::contains(&global_state.user_games, user_address), E_NO_ACTIVE_GAME);
        let user_game = smart_table::borrow(&global_state.user_games, user_address);
        assert!(user_game.game_over, E_GAME_OVER);
        
        // Register the completed game with pig_master
        pig_master::complete_game(user, user_game.total_score, user_game.round, user_game.turn);
        
        // Increment total games played
        global_state.total_games_played = global_state.total_games_played + 1;
    }

    /// The user wants to start a new game, end this one.
    entry fun reset_game(user: &signer) acquires GlobalGameState {
        let user_address = signer::address_of(user);
        let global_state = borrow_global_mut<GlobalGameState>(@pig_game_addr);
        
        // Reset or create new game state
        let new_game_state = UserGameState {
            last_roll: 0,
            turn_score: 0,
            total_score: 0,
            round: 0,
            turn: 0,
            game_over: false,
        };
        
        if (smart_table::contains(&global_state.user_games, user_address)) {
            *smart_table::borrow_mut(&mut global_state.user_games, user_address) = new_game_state;
        } else {
            smart_table::add(&mut global_state.user_games, user_address, new_game_state);
        };
    }

    // ======================== View (Read) Functions ========================

    #[view]
    /// Return the user's last roll value from the current game, 0 is considered no roll / hold
    public fun last_roll(user: address): u8 acquires GlobalGameState {
        let global_state = borrow_global<GlobalGameState>(@pig_game_addr);
        if (!smart_table::contains(&global_state.user_games, user)) {
            return 0
        };
        smart_table::borrow(&global_state.user_games, user).last_roll
    }

    #[view]
    /// Tells us which number round the game is on, this only resets when the game is reset
    ///
    /// This increments every time the user rolls the dice or holds
    public fun round(user: address): u64 acquires GlobalGameState {
        let global_state = borrow_global<GlobalGameState>(@pig_game_addr);
        if (!smart_table::contains(&global_state.user_games, user)) {
            return 0
        };
        smart_table::borrow(&global_state.user_games, user).round
    }

    #[view]
    /// Tells us which number turn the game is on, this only resets when the game is reset
    ///
    /// This increments every time the user rolls a 1 or holds
    public fun turn(user: address): u64 acquires GlobalGameState {
        let global_state = borrow_global<GlobalGameState>(@pig_game_addr);
        if (!smart_table::contains(&global_state.user_games, user)) {
            return 0
        };
        smart_table::borrow(&global_state.user_games, user).turn
    }

    #[view]
    /// Tells us whether the game is over for the user (the user has reached the target score)
    public fun game_over(user: address): bool acquires GlobalGameState {
        let global_state = borrow_global<GlobalGameState>(@pig_game_addr);
        if (!smart_table::contains(&global_state.user_games, user)) {
            return false
        };
        smart_table::borrow(&global_state.user_games, user).game_over
    }

    #[view]
    /// Return the user's current turn score, this is the score accumulated during the current turn.  If the player holds
    /// this score will be added to the total score for the game.
    public fun turn_score(user: address): u64 acquires GlobalGameState {
        let global_state = borrow_global<GlobalGameState>(@pig_game_addr);
        if (!smart_table::contains(&global_state.user_games, user)) {
            return 0
        };
        smart_table::borrow(&global_state.user_games, user).turn_score
    }

    #[view]
    /// Return the user's current total game score for the current game, this does not include the current turn score
    public fun total_score(user: address): u64 acquires GlobalGameState {
        let global_state = borrow_global<GlobalGameState>(@pig_game_addr);
        if (!smart_table::contains(&global_state.user_games, user)) {
            return 0
        };
        smart_table::borrow(&global_state.user_games, user).total_score
    }

    #[view]
    /// Return total number of games played within this game's context
    public fun games_played(): u64 acquires GlobalGameState {
        let global_state = borrow_global<GlobalGameState>(@pig_game_addr);
        global_state.total_games_played
    }

    #[view]
    /// Return total number of games played within this game's context for the given user
    public fun user_games_played(user: address): u64 {
        // Delegate to pig_master for user-specific game count
        let user_games_opt = pig_master::user_games_played(user);
        if (user_games_opt.is_some()) {
            user_games_opt.destroy_some()
        } else {
            0
        }
    }
}
