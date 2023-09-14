# Give 1.0001^n * 2^128
import decimal
from decimal import *

# Precision
getcontext().prec = 1000



D = Decimal

bp = D('1.0001')
shift = D(2)**128
# def price_pow(i):
#     bp**

def line(pow,exponent,price,hex_shifted_price,log2):
  print(f'({pow.rjust(10)}) {exponent.rjust(25)}: {price.rjust(50)}: 0x{hex_shifted_price.rjust(64,"0")} (log2: {log2.rjust(10)})')

def header():
  line("pow of 2","bp exponent","price","hex shifted price","log2")

def shift_for_half(pow):
  l2 = 127;
  if pow == 13:
    l2 = 126
  if pow == 14:
    l2 = 125
  if pow == 15:
    l2 = 123
  if pow == 16:
    l2 = 118
  if pow == 17:
    l2 = 109 
  if pow == 18:
    l2 = 90
  if pow == 19:
    l2 = 52
  extra_shift = 127-l2
  return 128 + extra_shift
  
def shift_for_full(pow):
  l2=254;
  if pow == 13:
    l2 = 253
  if pow == 14:
    l2 = 252
  if pow == 15:
    l2 = 250
  if pow == 16:
    l2 = 245
  if pow == 17:
    l2 = 236
  if pow == 18:
    l2 = 217
  if pow == 19:
    l2 = 179
  extra_shift = 255-l2
  return 254 + extra_shift

# 'half' or 'full'
precision = 'full'

def show_price(pow,sign):
  price = (bp**(sign*Decimal(2)**Decimal(pow)))
  shift = (shift_for_half(pow) if precision == 'half' else shift_for_full(pow))
  shifted_price = price * 2**shift
  f_hex_shifted_price = f'{int(shifted_price):x}'
  f_pow = f'{pow}'
  f_exponent = f'{2**pow:.15f}'
  f_price = f'{price:.25f}'
  log2 = shifted_price.ln()/Decimal(2).ln();
  f_log2 = f'{log2:.25f}'
  line(f_pow, f_exponent, f_price, f_hex_shifted_price,f_log2)

# print(r)
# h = f'{int(r):x}'.rjust(64,'0')
# print(h)
# print(f'{float(r):.0f}')
print('positive')
header()
for x in range(0,20):
  show_price(x,1)

print('negative')
header()
for x in range(0,20):
  show_price(x,-1)

# r = (bp**262144) * 2**128
# print(r)
# h = f'{int(r):x}'.rjust(64,'0')
# print(h)
# print(f'{float(r):.0f}')

log_bp_2_shifted_232 = Decimal(2).ln()/Decimal('1.0001').ln() * Decimal(2)**232



print(log_bp_2_shifted_232)

tick_shifted_232 = Decimal(221818) * Decimal(2)**232
tick_shifted_232 = Decimal(880341) * Decimal(2)**232

print()

print(tick_shifted_232)
print()
print(tick_shifted_232/log_bp_2_shifted_232)