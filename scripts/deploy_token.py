from brownie import LuncxToken, IterableMapping, accounts, chain, interface

def main():
    owner = accounts.load("dep")
    token = LuncxToken.deploy("0x3d04e17305A233597e0585E226C3E9174C0ACF4E", {"from":owner}, publish_source=True)
