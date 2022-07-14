from brownie import accounts, reverts, TestToken, TokenPresale
import pytest
from web3 import Web3


@pytest.fixture
def setup():
    owner = accounts[0]
    token = TestToken.deploy({"from": owner})
    presale = TokenPresale.deploy(token, Web3.toWei(15, "ether"), {"from": owner})
    zero = "0x0000000000000000000000000000000000000000"

    return owner, token, presale, zero


def test_whitelist(setup):
    (owner, token, presale, zero) = setup
    user1 = accounts[1]
    user2 = accounts[2]
    user3 = accounts[3]

    with reverts("Only whitelist"):
        presale.buyToken(zero, {"from": user1, "value": Web3.toWei(1, "ether")})

    assert presale.whitelistedUsers() == 0

    presale.addWhitelist(user2, {"from": owner})
    assert presale.whitelistedUsers() == 1
    assert presale.userInfo(user2)["whitelisted"] == True

    presale.buyToken(zero, {"from": user2, "value": Web3.toWei(1, "ether")})
    assert presale.userInfo(user2)["bought"] == Web3.toWei(1, "ether")
    assert presale.userInfo(user2)["claimed"] == 0

    presale.whitelistMultiple([user3, user1], {"frow": owner})
    assert presale.whitelistedUsers() == 3


def test_buys(setup):
    (owner, token, presale, zero) = setup
    user1 = accounts[1]
    user2 = accounts[2]
    user3 = accounts[3]
    user4 = accounts[4]

    presale.addWhitelist(user1, {"frow": owner})
    with reverts("Invalid Value Amount"):
        presale.buyToken(zero, {"from": user1, "value": Web3.toWei(0.001, "ether")})
    with reverts("Invalid Value Amount"):
        presale.buyToken(zero, {"from": user1, "value": Web3.toWei(16, "ether")})
    with reverts("Invalid Value Amount"):
        presale.buyToken(zero, {"from": user1, "value": Web3.toWei(1.001, "ether")})
    presale.buyToken(zero, {"from": user1, "value": Web3.toWei(15, "ether")})

    assert presale.totalRaise() == Web3.toWei(15, "ether")

    with reverts("Only whitelist"):
        presale.buyToken(zero, {"from": user2, "value": Web3.toWei(1, "ether")})
    with reverts("Invalid referrer"):
        presale.buyToken(user4, {"from": user2, "value": Web3.toWei(1, "ether")})

    presale.openForAll({"from": owner})
    presale.buyToken(zero, {"from": user2, "value": Web3.toWei(1, "ether")})

    assert presale.totalRaise() == Web3.toWei(16, "ether")
    assert presale.totalBuyers() == 2

    presale.buyToken(user1, {"from": user3, "value": Web3.toWei(2, "ether")})
    assert presale.totalRaise() == Web3.toWei(18, "ether")
    assert presale.totalBuyers() == 3
    assert presale.userInfo(user1)["referrals"] == 1
    assert presale.userInfo(user3)["referrer"] == user1

    presale.endTheSale({"from": owner})
    with reverts("Sale ended"):
        presale.buyToken(zero, {"from": user2})


def test_owner_claim(setup):
    (owner, token, presale, zero) = setup
    user1 = accounts[1]
    user2 = accounts[2]
    user3 = accounts[3]

    presale.openForAll({"from": owner})

    presale.buyToken(zero, {"from": user3, "value": Web3.toWei(2, "ether")})

    prevBal = owner.balance()

    presale.ownerClaim({"from": owner})

    assert prevBal + Web3.toWei(2, "ether") == owner.balance()


def test_user_claim(setup):
    (owner, token, presale, zero) = setup
    user1 = accounts[1]
    user2 = accounts[2]
    user3 = accounts[3]

    presale.openForAll({"from": owner})
    presale.buyToken(zero, {"from": user1, "value": Web3.toWei(2, "ether")})
    presale.buyToken(zero, {"from": user2, "value": Web3.toWei(2, "ether")})

    with reverts("Not yet"):
        presale.claimTokens({"from": user3})

    with reverts("Sale running"):
        presale.tokensClaimable({"from": owner})

    presale.endTheSale({"from": owner})

    with reverts("No tokens yet"):
        presale.tokensClaimable({"from": owner})

    token.approve(presale, Web3.toWei(1000, "ether"), {"from": owner})
    presale.addPrivateTokens(Web3.toWei(1000, "ether"), {"from": owner})

    assert presale.claimable() == False
    presale.tokensClaimable({"from": owner})
    assert presale.claimable() == True

    assert token.balanceOf(presale) == Web3.toWei(1000, "ether")

    with reverts("Already claimed"):
        presale.claimTokens({"from": user3})

    userbal = token.balanceOf(user1)
    assert userbal == 0
    presale.claimTokens({"from": user1})

    assert token.balanceOf(user1) == Web3.toWei(500, "ether")
    with reverts("Already claimed"):
        presale.claimTokens({"from": user1})
