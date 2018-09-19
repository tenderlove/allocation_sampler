require 'mkmf'
$CFLAGS << " -Wno-declaration-after-statement"
create_makefile('allocation_sampler')
