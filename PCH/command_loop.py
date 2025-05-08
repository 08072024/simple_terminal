#
# Variable/register setup
#
al = None
ah = None
bx = None
di = None
si = None

commands =  ['mov', 'crt', 'del', 'ent', 'sve', 'mod']
buffer =    ['d', 'o', 'v']

#
# FUNCTIONS
#
def command_found():
  print("The command was valid")

def unknown_command():
  print("The command was invalid")

#
# START
#
di = 0

while True:
  bx = 0
  si = commands[di]
  while True:
    al = si[bx]
    ah = buffer[bx]

    if (al != ah):
      break

    if bx == 2:
      command_found()
      break
    else:
      bx += 1
    
  if di == 5:
    unknown_command()
    break
  di += 1