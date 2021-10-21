// SPDX-License-Identifier: MIT
// Created by Flux Team

pragma solidity 0.6.8;
import "./lib/Ownable.sol";
import "./lib/SafeMath.sol";
import "./interface/IStake.sol";
import "./FluxApp.sol";
import { MarketStatus } from "./FluxStorage.sol";
import { IMarket } from "./market/Interface.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/upgrades/contracts/Initializable.sol";

enum TradeType { Borrow, Supply, Stake }
struct FluxMarketState {
    /// @dev 市场利息指数，或者抵押量
    uint256 index;
    /// @dev 更新时间
    uint256 blockTimestamp;
}

abstract contract FluxMintStorage {
    address public fluxAPP;

    /// @dev 团队解锁代币接收Flux账户
    address public teamFluxReceive;
    /// @dev 社区解锁代币接收Flux账户
    address public communityFluxReceive;
    /// @dev 上次解锁时间
    uint256 public lastUnlockTime;
    uint256 public lastUnlockBlock;

    uint16 public borrowFluxWeights_deprecated;
    uint16 public supplyFluxWeights_deprecated;
    uint16 public teamFluxWeights_deprecated;
    uint16 public communityFluxWeights_deprecated;

    ///@dev 记录三种交易下每个市场的借贷利息
    mapping(address => FluxMarketState[3]) public fluxIndexState;
    mapping(address => uint256) public fluxSeeds;
    ///@dev 为每个user标记上一次操作时的 fluxIndex
    mapping(address => mapping(address => uint256[3])) public fluxMintIndex;
    ///@dev 剩余未提 Flux
    mapping(address => uint256) public remainFluxByUser;

    mapping(address => uint256[3]) internal defaultMintIndex_deprecated;

    mapping(address => uint256) public genesisWeights;

    IERC20 public fluxToken;
}

abstract contract FluxMintBase is Ownable, Initializable, FluxMintStorage {
    using SafeMath for uint256;

    address public constant TEAM_COMMUNITY_WEIGHT_SLOT = 0x16c691bE1E5548dE0aC19e02C68A935C2D9FdEcC; // Random
    uint256 private constant FLUX_START_TIME = 1615896000; // 初始挖块时间
    uint256 private constant FLUX_FIRST_MINT = 261891399135344344; // flux初始区块挖矿量
    uint256 private constant FLUX_PER_DEC = 2143347049; // flux挖矿每秒递减量
    uint256 private constant FLUX_END_TIME = 1738084051;

    uint16 private constant WEIGHT_UNIT = 1e4;
    uint256 private constant DECIMAL_UNIT = 1e18;

    /**
     * @notice Flux分配权重修改
     * @param borrow 借款挖矿分配比
     * @param supply 借款挖矿分配比
     * @param stake 抵押挖矿分配比
     * @param team 团队分配比
     * @param community 社区分配比
     */
    event FluxWeightsChanged(uint16 borrow, uint16 supply, uint16 stake, uint16 team, uint16 community);
    event GenesisMintWeightsChanged(address pool, uint256 oldWeight, uint256 newWeight);
    /**
     * @notice Flux Token 在不同池中的分配比更新
     * @param pool 挖矿池地址（借贷池或者抵押池）
     * @param oldSeed 原分配比
     * @param newSeed 新分配比
     */
    event FluxSeedChanged(address indexed pool, uint256 oldSeed, uint256 newSeed);
    event FluxMintIndexChanged(address indexed pool, TradeType indexed kind, uint256 startBlock, uint256 endBlock, uint256 factor, uint256 weights, uint256 seed, uint256 fluxMinted, uint256 oldIndex, uint256 newIndex);

    /**
     * @notice 分发Flux代币到LPs
     * @param pool 挖矿池地址
     * @param kind 涉及到的交易类型：0-借款，1-存款，2-抵押
     * @param user Flux接收者
     * @param distribution 分发Flux数量
     * @param currIndex 当前该挖矿池的 kind 类型交易对应的Flux开采指数
     */
    event DistributedFlux(address indexed pool, TradeType indexed kind, address indexed user, uint256 distribution, uint256 currIndex);

    event UnlockFlux(address recipient, uint256 amount, uint256 weights);

    /**
     * @notice Flux 被管理员成合约中转走
     */
    event FluxGranted(address recipient, uint256 amount);

    event TeamAdressChanged(address oldTeam, address oldComm, address newTeam, address newComm);

    modifier onlyAppOrAdmin() {
        require(msg.sender == fluxAPP || msg.sender == owner(), "Ownable: caller is not the owner");
        _;
    }

    function initialize(
        address admin_,
        address fluxAPP_,
        IERC20 _fluxToken
    ) external initializer {
        initOwner(admin_);

        fluxAPP = fluxAPP_;
        fluxToken = _fluxToken;
        lastUnlockBlock = block.timestamp;
        lastUnlockTime = block.timestamp;
    }

    function setFluxToken(IERC20 token) external onlyOwner {
        fluxToken = token; //允许为空
    }

    /**
     * @notice 更新团队和社区代币接收地址
     * @param team 新的团队代币接收地址
     * @param comm 新的社区代币接收地址
     */
    function resetTeamAdress(address team, address comm) external onlyOwner {
        require(team != address(0), "EMPTY_ADDRESS");
        require(comm != address(0), "EMPTY_ADDRESS");
        emit TeamAdressChanged(teamFluxReceive, communityFluxReceive, team, comm);
        teamFluxReceive = team;
        communityFluxReceive = comm;
        _unlockDAOFlux();
    }

    /**
     * @notice 管理员转移合约中存在的Flux到指定账户
     */
    function grantFlux(address recipient, uint256 amount) external onlyOwner {
        _transferFluxToken(recipient, amount);
        emit FluxGranted(recipient, amount);
    }

    /**
     *@notice 批量修改挖矿产出分配比例
     */
    function batchSetPoolWeight(address[] calldata pools, uint256[] calldata weights) external onlyOwner {
        require(pools.length == weights.length, "INVALID_INPUT");
        for (uint256 i = 0; i < pools.length; i++) {
            _setPoolSeed(pools[i], weights[i], true);
        }
    }

    function batchSetPoolGenesisWeight(address[] calldata pools, uint256[] calldata weights) external onlyOwner {
        require(pools.length == weights.length, "INVALID_INPUT");
        for (uint256 i = 0; i < pools.length; i++) {
            _setPoolSeed(pools[i], weights[i], false);
        }
    }

    function setPoolSeed(address pool, uint256 seed) external onlyAppOrAdmin {
        _setPoolSeed(pool, seed, true);
    }

    function _setPoolSeed(
        address pool,
        uint256 seed,
        bool isBase
    ) private {
        splitTowWeight(seed); //try check
        //refresh
        if (pool == TEAM_COMMUNITY_WEIGHT_SLOT) {
            _unlockDAOFlux();
        } else if (FluxApp(fluxAPP).mktExist(IMarket(pool))) {
            //  借贷池
            _refreshFluxMintIndexAtMarket(pool);
        } else {
            // Stake
            _refreshFluxMintIndex(pool, TradeType.Stake, 0);
        }

        if (isBase) {
            uint256 oldSeed = fluxSeeds[pool];
            fluxSeeds[pool] = seed;
            emit FluxSeedChanged(pool, oldSeed, seed);
        } else {
            emit GenesisMintWeightsChanged(pool, genesisWeights[pool], seed);
            genesisWeights[pool] = seed;
        }
    }

    function removePool(address pool) external onlyAppOrAdmin {
        uint256 oldSeed = fluxSeeds[pool];
        delete fluxSeeds[pool];
        emit FluxSeedChanged(pool, oldSeed, 0);
    }

    function claimDaoFlux() external {
        //对时间无直接依赖，仅仅是一个解锁间隔检查而已
        require(lastUnlockTime < block.timestamp, "REPEAT_UNLOCK");
        _unlockDAOFlux();
    }

    function refreshFluxMintIndex(address pool, uint256 interestIndex) external onlyAppOrAdmin {
        _refreshFluxMintIndex(pool, TradeType.Borrow, interestIndex);
        _refreshFluxMintIndex(pool, TradeType.Supply, 0);
    }

    function _refreshFluxMintIndexAtMarket(address pool) private returns (uint256 interestIndex) {
        IMarket(pool).calcCompoundInterest();
        interestIndex = IMarket(pool).interestIndex();
        _refreshFluxMintIndex(pool, TradeType.Borrow, interestIndex);
        _refreshFluxMintIndex(pool, TradeType.Supply, 0);
    }

    /**
     * @notice 刷新
     */
    function refreshPoolFluxMintIndex() external {
        require(msg.sender == tx.origin, "SENDER_NOT_HUMAN");

        FluxApp app = FluxApp(fluxAPP);
        {
            address[] memory list = app.getMarketList();
            for (uint256 i = 0; i < list.length; i++) {
                _refreshFluxMintIndexAtMarket(list[i]);
            }
        }

        {
            address[] memory pools = app.getStakePoolList();
            for (uint256 i = 0; i < pools.length; i++) {
                _refreshFluxMintIndex(pools[i], TradeType.Stake, 0);
            }
        }
    }

    /**
     * @dev 提取指定钱包所有待领取的Flux代币
     */
    function claimFlux() external {
        FluxApp app = FluxApp(fluxAPP);
        address sender = msg.sender;
        {
            address[] memory list = app.getMarketList();
            for (uint256 i = 0; i < list.length; i++) {
                (uint256 ftokens, uint256 borrows, ) = IMarket(list[i]).getAcctSnapshot(sender);
                if (ftokens == 0 && borrows == 0) {
                    continue;
                }
                uint256 interestIndex = _refreshFluxMintIndexAtMarket(list[i]);
                if (borrows > 0) _distributeFlux(list[i], TradeType.Borrow, sender, interestIndex);
                if (ftokens > 0) _distributeFlux(list[i], TradeType.Supply, sender, 0);
            }
        }

        {
            address[] memory pools = app.getStakePoolList();
            for (uint256 i = 0; i < pools.length; i++) {
                uint256 stake = IStake(pools[i]).balanceOf(sender);
                if (stake > 0) {
                    _refreshFluxMintIndex(pools[i], TradeType.Stake, 0);
                    _distributeFlux(pools[i], TradeType.Stake, sender, 0);
                }
            }
        }
        uint256 balance = remainFluxByUser[sender];
        remainFluxByUser[sender] = 0;
        // require(balance > 0, "FLUX_BALANCE_IS_ZERO");
        _transferFluxToken(sender, balance);
    }

    function settleOnce(
        address pool,
        TradeType kind,
        address user
    ) external onlyAppOrAdmin {
        uint256 index;
        if (kind == TradeType.Borrow) {
            index = IMarket(pool).interestIndex();
        }

        _refreshFluxMintIndex(pool, kind, index);
        _distributeFlux(pool, kind, user, index);
    }

    struct MintVars {
        address pool;
        TradeType kind;
        uint256 newIndex;
        uint256 factor;
        uint256 weights;
        uint256 seed;
        uint256 fluxMinted;
        uint256 height;
        uint256 low;
    }

    function _calcFluxMintIndex(
        address pool,
        TradeType kind,
        uint256 interestIndex
    )
        private
        view
        returns (
            uint256, //newIndex,
            uint256, //factor,
            uint256, //weights,
            uint256, //seed,
            uint256 //fluxMinted
        )
    {
        FluxMarketState storage state = fluxIndexState[pool][uint8(kind)];
        uint256 stateTime = state.blockTimestamp;
        uint256 currentTime = block.timestamp;
        uint256 deltaTimes = currentTime.sub(stateTime);
        if (deltaTimes == 0) {
            return (state.index, 0, 0, 0, 0);
        }

        MintVars memory vars;
        vars.kind = kind;
        vars.pool = pool;
        vars.seed = fluxSeeds[vars.pool];

        (vars.height, vars.low) = splitTowWeight(vars.seed);

        if (vars.kind == TradeType.Borrow) {
            IMarket mkt = IMarket(vars.pool);
            vars.factor = interestIndex > 0 ? mkt.totalBorrows().mul(DECIMAL_UNIT).div(interestIndex) : 0;
            vars.weights = vars.height;
        } else if (vars.kind == TradeType.Supply) {
            vars.factor = IMarket(vars.pool).totalSupply();
            vars.weights = vars.low;
        } else if (vars.kind == TradeType.Stake) {
            vars.factor = IStake(vars.pool).totalSupply(); //read last round.
            vars.weights = vars.low;
        } else {
            revert("UNKNOWN_KIND");
        }

        if (vars.factor > 0) {
            uint256 base = fluxsMinedBase(stateTime, currentTime);
            uint256 poolMinted = base.mul(vars.weights);
            (uint256 genusis, uint256 poolGenusis) = _calcGenusisMinted(vars.pool, vars.kind, stateTime, currentTime);
            // new index=  fluxAmount  * weights / factor + oldIndex
            uint256 oldIndex = state.index;
            vars.newIndex = (poolMinted.add(poolGenusis)).div(vars.factor).add(oldIndex);
            vars.fluxMinted = base + genusis;
            return (vars.newIndex, vars.factor, vars.weights, vars.seed, vars.fluxMinted);
        } else {
            return (state.index, vars.factor, vars.weights, vars.seed, 0);
        }
    }

    function _calcGenusisMinted(
        address pool,
        TradeType kind,
        uint256 fromBlock,
        uint256 toBlock
    ) private view returns (uint256 mined, uint256 poolMinted) {
        mined = fluxsMinedGenusis(fromBlock, toBlock);
        if (mined == 0) {
            return (0, 0);
        }
        (uint256 height, uint256 low) = splitTowWeight(genesisWeights[pool]);
        uint256 weight;
        if (kind == TradeType.Borrow) {
            weight = height;
        } else if (kind == TradeType.Supply) {
            weight = low;
        } else if (kind == TradeType.Stake) {
            weight = low;
        }
        poolMinted = mined.mul(weight);
    }

    function _refreshFluxMintIndex(
        address pool,
        TradeType kind,
        uint256 interestIndex
    ) private {
        FluxMarketState storage state = fluxIndexState[pool][uint8(kind)];
        uint256 oldNumber = state.blockTimestamp;
        if (oldNumber == block.timestamp) {
            return;
        }
        (uint256 newIndex, uint256 factor, uint256 weights, uint256 seed, uint256 fluxMinted) = _calcFluxMintIndex(pool, kind, interestIndex);
        uint256 oldIndex = state.index;
        state.index = newIndex;
        state.blockTimestamp = block.timestamp;

        emit FluxMintIndexChanged(pool, kind, oldNumber, block.timestamp, factor, weights, seed, fluxMinted, oldIndex, newIndex);
    }

    function _unlockDAOFlux() private returns (bool) {
        address team = teamFluxReceive;
        address comm = communityFluxReceive;
        require(team != address(0), "TEAM_RECEIVER_IS_EMPTY");
        require(comm != address(0), "COMM_RECEIVER_IS_EMPTY");

        uint256 minted = calcFluxsMined(lastUnlockBlock, block.timestamp);
        //never overflow
        (uint256 teamWeight, uint256 communityWeight) = splitTowWeight(fluxSeeds[TEAM_COMMUNITY_WEIGHT_SLOT]);

        uint256 teamAmount = minted.mul(teamWeight).div(DECIMAL_UNIT);
        uint256 communityAmount = minted.mul(communityWeight).div(DECIMAL_UNIT);

        lastUnlockTime = block.timestamp;
        lastUnlockBlock = block.timestamp;

        emit UnlockFlux(comm, communityAmount, communityWeight);
        emit UnlockFlux(team, teamAmount, teamWeight);

        _transferFluxToken(team, teamAmount);
        _transferFluxToken(comm, communityAmount);
    }

    /**
      @notice 计算可获得的FLUX奖励
     */
    function getFluxRewards(
        address pool,
        TradeType kind,
        address user
    ) external view returns (uint256 reward) {
        uint256 interestIndex;
        if (kind == TradeType.Borrow) {
            interestIndex = IMarket(pool).interestIndex();
        }
        (uint256 newIndex, , , , ) = _calcFluxMintIndex(pool, kind, interestIndex);
        reward = _calcRewardFlux(pool, kind, user, interestIndex, newIndex);
    }

    /**
     @dev 计算当前指定市场交易可获得的奖励
     */
    function _calcRewardFlux(
        address pool,
        TradeType kind,
        address user,
        uint256 interestIndex,
        uint256 currIndex
    ) private view returns (uint256 reward) {
        if (currIndex == 0) currIndex = fluxIndexState[pool][uint8(kind)].index;
        uint256 lastIndex = fluxMintIndex[pool][user][uint256(kind)];
        uint256 settleIndex = currIndex.sub(lastIndex);
        if (settleIndex == 0) {
            return 0;
        }

        uint256 weights;
        if (kind == TradeType.Borrow) {
            IMarket mkt = IMarket(pool);
            //  weights =  borrow/totalBorrow
            //  index =   totalBorrow/interestIndex
            weights = interestIndex > 0 ? mkt.borrowAmount(user).mul(DECIMAL_UNIT).div(interestIndex) : 0;
        } else if (kind == TradeType.Supply) {
            weights = IMarket(pool).balanceOf(user);
        } else if (kind == TradeType.Stake) {
            weights = IStake(pool).balanceOf(user);
        } else {
            revert("UNKNOWN_KIND");
        }
        if (weights == 0) {
            return 0;
        }

        // 结算的FLUX = 结余+本次奖励
        reward = settleIndex.mul(weights).div(DECIMAL_UNIT);
    }

    function _distributeFlux(
        address pool,
        TradeType kind,
        address user,
        uint256 interestIndex
    ) private {
        // 结算的FLUX = 结余+本次奖励
        uint256 distribution = _calcRewardFlux(pool, kind, user, interestIndex, 0);
        remainFluxByUser[user] = remainFluxByUser[user].add(distribution);
        uint256 index = fluxIndexState[pool][uint8(kind)].index;
        fluxMintIndex[pool][user][uint256(kind)] = index;

        if (distribution > 0) emit DistributedFlux(pool, kind, user, distribution, index);
    }

    /**
     * @dev 计算一个时间区间内[fromTime,endTime)所能释放的Flux数量。
     *      挖矿总量为21000000个，挖矿周期为365*4天共计4年，其中500万属于头矿包。
     *      挖矿数按区块递减，换算后每日挖矿量递减16flux
     * @param fromTime 计算的区块偏移，从零开始。使用from区块号减去初始挖矿区块号得到。
     * @param endTime 计算结束区块时间戳，同上。
     * @return 返回区间[fromTime,endTime)的挖矿总量
     */
    function calcFluxsMined(uint256 fromTime, uint256 endTime) public pure virtual returns (uint256) {
        uint256 base = fluxsMinedBase(fromTime, endTime);
        uint256 genusis = fluxsMinedGenusis(fromTime, endTime);
        return base.add(genusis);
    }

    function fluxsMinedBase(uint256 fromTime, uint256 endTime) public pure virtual returns (uint256) {
        fromTime = SafeMath.max(fromTime, FLUX_START_TIME);
        endTime = SafeMath.min(endTime, FLUX_END_TIME);
        if (endTime <= fromTime) {
            return 0;
        }
        // s= [fromTime,endTime)
        // fromTime < endTime =>  fromTime <= endTime-1;
        uint256 sum;
        uint256 a1 = _fluxBlock(fromTime);
        uint256 an = _fluxBlock(endTime - 1);
        // s= (a+ a_n) * (n-1)/2;
        sum = ((a1 + an) * (endTime - fromTime)) / 2;
        return sum;
    }

    function fluxsMinedGenusis(uint256 fromTime, uint256 endTime) public pure virtual returns (uint256) {
        revert("NEED_OVERRIDE");
    }

    function _fluxBlock(uint256 _time) private pure returns (uint256) {
        //  an= a1-(n-1)*d
        return FLUX_FIRST_MINT.sub(_time.sub(FLUX_START_TIME).mul(FLUX_PER_DEC));
    }

    function _transferFluxToken(address receiver, uint256 amount) private {
        require(fluxToken.transfer(receiver, amount), "TRANSDFER_FAILED");
    }

    function getPoolSeed(address pool) external view returns (uint256 height, uint256 low) {
        return splitTowWeight(fluxSeeds[pool]);
    }

    function getGenesisWeight(address pool) external view returns (uint256 height, uint256 low) {
        return splitTowWeight(genesisWeights[pool]);
    }

    function splitTowWeight(uint256 value) public pure returns (uint256 height, uint256 low) {
        height = value >> 128;
        low = uint256(value << 128) >> 128;

        // 不超过 100% *1e18;
        require(height < DECIMAL_UNIT && low < DECIMAL_UNIT, "INVALID_WEIGHT");
    }

    function connectTwoUint128(uint128 a, uint128 b) public pure returns (uint256) {
        // u256  bytes32
        uint256 a2 = uint256(a) << 128;
        return a2 + uint256(b);
    }
}

contract FluxMint is FluxMintBase {
    function fluxsMinedGenusis(uint256, uint256) public pure override returns (uint256) {
        return 0;
    }
}

contract FluxMintOnArb is FluxMintBase {
    uint256 private constant GENESISMINING_STAET_TIME = uint256(-1); //头矿开始时间
    uint256 private constant GENESISMINING_TIMES = 14 days; //头矿14天
    uint256 private constant GENESISMINING_END_TIME = GENESISMINING_STAET_TIME + GENESISMINING_TIMES; //头矿截止时间
    uint256 private constant GENESISMINING_AMOUNT = 750000 * 1e18; //头矿增量FLUX
    uint256 private constant GENESISMINING_ONE = GENESISMINING_AMOUNT / GENESISMINING_TIMES; //头矿每秒可多额外产出FLUX

    function fluxsMinedGenusis(uint256 fromTime, uint256 endTime) public pure override returns (uint256) {
        fromTime = SafeMath.max(fromTime, GENESISMINING_STAET_TIME);
        endTime = SafeMath.min(endTime, GENESISMINING_END_TIME);
        if (endTime <= fromTime) {
            return 0;
        }
        return (endTime - fromTime).mul(GENESISMINING_ONE);
    }
}

contract FluxMintOnPolygon is FluxMintBase {
    uint256 private constant GENESISMINING_STAET_TIME = 1634644800; //头矿开始时间 2021年10月19日 20:00:00
    uint256 private constant GENESISMINING_TIMES = 14 days; //头矿14天
    uint256 private constant GENESISMINING_END_TIME = GENESISMINING_STAET_TIME + GENESISMINING_TIMES; //头矿截止时间
    uint256 private constant GENESISMINING_AMOUNT = 21000 * 1e18; //头矿增量FLUX
    uint256 private constant GENESISMINING_ONE = GENESISMINING_AMOUNT / GENESISMINING_TIMES; //头矿每秒可多额外产出FLUX

    function fluxsMinedGenusis(uint256 fromTime, uint256 endTime) public pure override returns (uint256) {
        fromTime = SafeMath.max(fromTime, GENESISMINING_STAET_TIME);
        endTime = SafeMath.min(endTime, GENESISMINING_END_TIME);
        if (endTime <= fromTime) {
            return 0;
        }
        return (endTime - fromTime).mul(GENESISMINING_ONE);
    }
}

contract FluxMintOnOptimism is FluxMintBase {
    uint256 private constant GENESISMINING_STAET_TIME = 8888888800;
    uint256 private constant GENESISMINING_TIMES = 14 days; //头矿14天
    uint256 private constant GENESISMINING_END_TIME = GENESISMINING_STAET_TIME + GENESISMINING_TIMES; //头矿截止时间
    uint256 private constant GENESISMINING_AMOUNT = 21000 * 1e18; //头矿增量FLUX
    uint256 private constant GENESISMINING_ONE = GENESISMINING_AMOUNT / GENESISMINING_TIMES; //头矿每秒可多额外产出FLUX

    function fluxsMinedGenusis(uint256 fromTime, uint256 endTime) public pure override returns (uint256) {
        fromTime = SafeMath.max(fromTime, GENESISMINING_STAET_TIME);
        endTime = SafeMath.min(endTime, GENESISMINING_END_TIME);
        if (endTime <= fromTime) {
            return 0;
        }
        return (endTime - fromTime).mul(GENESISMINING_ONE);
    }
}
