commands =          'movcrtdelentsvemod'
commands_file_bin = ['mov', 'crt', 'del', 'ent', 'sve', 'mod']
buffer =            input("Enter station: ")

def outer_loop(bx, invisible_index, cx):
  if bx >= len(commands):
      unknown_command()
  inner_loop(al=None, di=0, bx=bx, invisible_index=invisible_index, cx=cx)

def inner_loop(al, di, bx, invisible_index, cx):
  if di == 3:
      command_found(cx)
      return

  ah = buffer[di]
  al = commands[invisible_index]

  if al != ah:
      end(bx=bx, di=di, cx=cx)
      return

  inner_loop(al=al, di=di+1, bx=bx, invisible_index=invisible_index+1, cx=cx+1)

def end(bx, di, cx):
    ax = 3 - di
    cx += ax  # Skip rest of command
    outer_loop(bx=bx+1, invisible_index=cx, cx=cx)

def command_found(cx):
  print(f"Loading into {commands_file_bin[int((cx - cx % 3) / 3-1)]}")

def unknown_command():
  print(buffer, "is not a known station of this OS.")
  while True:
    continue

# Start
outer_loop(bx=0, invisible_index=0, cx=0)