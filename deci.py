# Give 1.0001^n * 2^128
import decimal
from decimal import *

# Precision
getcontext().prec = 1000



D = Decimal

bp = D('1.0001')

def s(x,u):
  r = (bp**(u*Decimal(2)**Decimal(x))) * 2**128
  rr = (bp**(u*Decimal(2)**Decimal(x)))
  h = f'{int(r):x}'
  ee = f'{x}'
  e = f'{2**x:.15f}'
  m = f'{rr:.25f}'
  print(f'({ee.rjust(4)}) {e.rjust(25)}: {m.rjust(30)}: 0x{h.rjust(64,"0")}')

# print(r)
# h = f'{int(r):x}'.rjust(64,'0')
# print(h)
# print(f'{float(r):.0f}')
print('positive')
for x in range(0,20):
  s(x,1)

print('negative')
for x in range(0,20):
  s(x,-1)

# r = (bp**262144) * 2**128
# print(r)
# h = f'{int(r):x}'.rjust(64,'0')
# print(h)
# print(f'{float(r):.0f}')
