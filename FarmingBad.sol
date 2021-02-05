// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./MethToken.sol";

/*

___________                    .__                 ___.               .___
\_   _____/____ _______  _____ |__| ____    ____   \_ |__ _____     __| _/
 |    __) \__  \\_  __ \/     \|  |/    \  / ___\   | __ \\__  \   / __ | 
 |     \   / __ \|  | \/  Y Y  \  |   |  \/ /_/  >  | \_\ \/ __ \_/ /_/ | 
 \___  /  (____  /__|  |__|_|  /__|___|  /\___  /   |___  (____  /\____ | 
     \/        \/            \/        \//_____/        \/     \/      \/ 

*/



// FarmingBad is the master of METH. He can make METH and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once METH is sufficiently
// distributed and the community can show to govern itself.
contract FarmingBad is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of METHs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accMETHPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accMETHPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. METHs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that METHs distribution occurs.
        uint256 accMETHPerShare; // Accumulated METHs per share, times 1e12. See below.
    }


    METHToken public METH;    // The METH TOKEN!
    address public devaddr;    // Dev address.

    mapping(address => bool) public lpTokenExistsInPool;    // Track all added pools to prevent adding the same pool more then once.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;    // Info of each user that stakes LP tokens.

    uint256 public totalAllocPoint = 0;    // Total allocation points. Must be the sum of all allocation points in all pools.

    uint256 public constant startBlock = 11798576;    // The block number when METH mining starts. WILL BE 
    uint256 public bonusEndBlock = 11798576;
    
    uint256 public constant DEV_TAX = 5;
    uint256 public constant BONUS_MULTIPLIER = 1;

	uint256 public methPerBlock = 46e18;
	uint256 public berhaneValue = 35e12;
	uint256 public lastBlockUpdate = 0; // the last block when RewardPerBlock was updated with the berhaneValue

    PoolInfo[] public poolInfo;    // Info of each pool.

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    modifier onlyDev() {
        require(devaddr == _msgSender(), "not dev");
        _;
    }

    constructor(
        METHToken _METH,
        address _devaddr
    ) public {
        METH = _METH;
        devaddr = _devaddr;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate) public onlyOwner {
        require(!lpTokenExistsInPool[address(_lpToken)], "MasterChef: LP Token Address already exists in pool");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accMETHPerShare: 0
        }));

        lpTokenExistsInPool[address(_lpToken)] = true;
    }

    function updateDevAddress(address _devAddress) public onlyDev {
        devaddr = _devAddress;
    }

    // Add a pool manually for pools that already exists, but were not auto added to the map by "add()".
    function updateLpTokenExists(address _lpTokenAddr, bool _isExists) external onlyOwner {
        lpTokenExistsInPool[_lpTokenAddr] = _isExists;
    }

    // Update the given pool's METH allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }
    
    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_to <= bonusEndBlock) {
            return _to.sub(_from).mul(BONUS_MULTIPLIER);
        } else if (_from >= bonusEndBlock) {
            return _to.sub(_from);
        } else {
            return bonusEndBlock.sub(_from).mul(BONUS_MULTIPLIER).add(
                _to.sub(bonusEndBlock)
            );
        }
    }

    // View function to see pending METHs on frontend.
    function pendingMETH(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accMETHPerShare = pool.accMETHPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 blocksToReward = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 methReward = blocksToReward.mul(methPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accMETHPerShare = accMETHPerShare.add(methReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accMETHPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        
        // Init the first block when berhaneValue has been updated
        if (lastBlockUpdate == 0) {
            lastBlockUpdate = block.number;
        }

        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        
        // Get number of blocks since last update of methPerBlock
        uint256 BlocksToUpdate = block.number - lastBlockUpdate;

        // Adjust Berhane depending on number of blocks to update
        uint256 Berhane = (BlocksToUpdate).mul(berhaneValue);
        
        // Set the new number of methPerBlock with Berhane
        methPerBlock = methPerBlock.sub(Berhane);
        
        // Check how many blocks have to be rewarded since the last pool update
        uint256 blocksToReward = getMultiplier(pool.lastRewardBlock, block.number);
        
        uint256 CompensationSinceLastRewardUpdate = 0;
        if (BlocksToUpdate > 0)
        {
            CompensationSinceLastRewardUpdate = BlocksToUpdate.mul(Berhane);
        }
        uint256 methReward = blocksToReward.mul(methPerBlock.add(CompensationSinceLastRewardUpdate)).mul(pool.allocPoint).div(totalAllocPoint);

        METH.mint(address(this), methReward);
        pool.accMETHPerShare = pool.accMETHPerShare.add(methReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
        lastBlockUpdate = block.number;
    }

    // Deposit LP tokens to FarmingBad for METH allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accMETHPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeMethTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            uint256 _taxAmount = _amount.mul(DEV_TAX).div(100);
            _amount = _amount.sub(_taxAmount);
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            pool.lpToken.safeTransferFrom(address(msg.sender), address(devaddr), _taxAmount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accMETHPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from FarmingBad.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accMETHPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeMethTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accMETHPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
        
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe METH transfer function, just in case if rounding error causes pool to not have enough METHs.
    function safeMethTransfer(address _to, uint256 _amount) internal {
        uint256 MethBal = METH.balanceOf(address(this));
        if (_amount > MethBal) {
            METH.transfer(_to, MethBal);
        } else {
            METH.transfer(_to, _amount);
        }
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }
}
