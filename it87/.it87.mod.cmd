savedcmd_it87.mod := printf '%s\n'   it87.o | awk '!x[$$0]++ { print("./"$$0) }' > it87.mod
