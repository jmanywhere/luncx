from brownie import LuncxToken, IterableMapping, accounts, chain, interface
import pytest
from web3 import Web3

@pytest.fixture
def setup():
    owner = accounts[0]
    mkt = accounts[1]
    user1 = accounts[2]
    user2 = accounts[3]
    user3 = accounts[4]
    user4 = accounts[5]

    itLib = IterableMapping.deploy({"from": owner})
    token = LuncxToken.deploy(mkt, {"from":owner})

    token.transfer(user1, Web3.toWei(1_000_000, "ether"), {"from": owner})
    token.transfer(user2, Web3.toWei(1_000_000, "ether"), {"from": owner})
    token.transfer(user3, Web3.toWei(1_000_000, "ether"), {"from": owner})
    token.transfer(user4, Web3.toWei(1_000_000, "ether"), {"from": owner})

    router = interface.IUniswapV2Router02(token.uniswapV2Router())
    token.approve(router, Web3.toWei(1_000_000_000, "ether"),{"from": owner})

    router.addLiquidityETH(token, Web3.toWei(1_000_000, "ether"), Web3.toWei(1_000_000, "ether"), Web3.toWei(30, "ether"), owner, chain.time() + 3600, {"from": owner, "value":Web3.toWei(30, "ether") })
    return token, mkt, user1, user2, user3, user4, router, owner

def test_fee_taken(setup):
    (token, mkt, user1, user2, user3, user4, router, owner) = setup

    user5 = accounts[6]

    token.transfer(user5, Web3.toWei(500_000, "ether"), {"from": user1})

    assert token.balanceOf(user1) == Web3.toWei(500_000, "ether")
    assert token.balanceOf(user5) == Web3.toWei(500_000 * 91/100, "ether")
    # All tokens swapped because transfer exceeds min to swap
    assert token.balanceOf(token) == 0

    token.startAntiDump({"from": owner})
    user6 = accounts[7]
    user7 = accounts[8]
    token.transfer(user6, Web3.toWei(50, "ether"), {"from": user1})
    assert token.balanceOf(user6) == Web3.toWei(25, "ether")
    assert token.balanceOf(token) == Web3.toWei(25, "ether")
    assert token.burnAmount() == Web3.toWei(5, "ether")
    assert token.rewardsAmount() == Web3.toWei(10, "ether")
    assert token.marketingAmount() == Web3.toWei(10, "ether")

    chain.mine(blocks=10, timedelta=3600*4 + 1)
    token.transfer(user7, Web3.toWei(100, "ether"), {"from": user1})
    assert token.balanceOf(user7) == Web3.toWei(91, "ether")



