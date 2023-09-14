# PROBLEM: PYTHON PRECISION IS TOO LOW -- use decimal module?
def s(b,multiplier): 
    prefront = f'2^{b}'.rjust(6)
    n = 1.0001*(2**b)*(2**128)
    print(n)
    print(f'{n:.0f}')
    front = f'0x{(2**b):x}'.rjust(9,' ')
    raw = f"{int(1.0001**(multiplier*(2**b)) * 2**128):x}".rjust(64,'0')
    content = f'0x{raw}'
    return f'{prefront} | {front}: {content}'

print("positive")
for x in range(0,21):
    print(s(x,1))

print("")
print("negative")
for x in range(0,21):
    print(s(x,-1))
