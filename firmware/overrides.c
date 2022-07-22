#include "config.h"
#include "statusword.h"
#include "ps2.h"
#include "keyboard.h"
#include "uart.h"
#include "interrupts.h"
#include "configstring.h"
#include "diskimg.h"

#include <stdio.h>
#include <string.h>

#include "c64keys.c"

int LoadROM(const char *fn);

int UpdateKeys(int blockkeys)
{
	static int init=0;
	if(!init)
	{
		init=1;
		initc64keys();
	}
	handlec64keys();
	return(HandlePS2RawCodes(blockkeys));
}

