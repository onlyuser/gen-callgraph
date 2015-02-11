#!/bin/bash

CMD=`basename $0`

show_help()
{
    echo "Usage: $CMD <BINARY>"
}

if [ $# -ne 1 ]; then
    echo "Fail! -- Expecting 1 argument! ==> $@"
    show_help
    exit 1
fi

if [ -z "`which readelf`" ]; then
    echo "Error: Requires \"readelf\""
    exit 1
fi

if [ -z "`which objdump`" ]; then
    echo "Error: Requires \"objdump\""
    exit 1
fi

if [ -z "`which c++filt`" ]; then
    echo "Error: Requires \"c++filt\""
    exit 1
fi

if [ -z "`which dot`" ]; then
    echo "Error: Requires \"dot\""
    exit 1
fi

EXEC=$1

if [ ! -f "$EXEC" ]; then
    echo "Error: $EXEC doesn't exist!"
    exit 1
fi

#http://stackoverflow.com/questions/19071461/disassemble-raw-x64-machine-code

SYMBOLS_FILE="`mktemp`"
ASM_FILE="`mktemp`"
trap "rm $SYMBOLS_FILE $ASM_FILE" EXIT

#readelf $EXEC --all > $SYMBOLS_FILE
readelf $EXEC --headers --symbols > $SYMBOLS_FILE

#objdump -D -b binary -mi386 -Maddr16,data16 $EXEC > $ASM_FILE
objdump -D -b binary -mi386:x86-64 $EXEC > $ASM_FILE

ENTRY_POINT_LINE="`grep "Entry point address:" $SYMBOLS_FILE`"
ENTRY_POINT_ADDR="`echo \"$ENTRY_POINT_LINE\" | cut -d':' -f2 | tr -d ' ' | sed 's/^0x400//g'`"

FUNC_TRIPLE_LIST=""
FOUND_SYMTAB=0
while read SYMBOLS_FILE_LINE; do
    if [ "$FOUND_SYMTAB" == 0 ]; then
        if [[ "$SYMBOLS_FILE_LINE" =~ "Symbol table '.symtab'" ]]; then
            FOUND_SYMTAB=1
        else
            continue
        fi
    fi
    SYMBOLS_TUPLE="`echo \"$SYMBOLS_FILE_LINE\" | sed 's/[ ]\+/ /g'`"
    if [ "`echo \"$SYMBOLS_TUPLE\" | cut -d' ' -f4`" == "FUNC" ] &&
       [ "`echo \"$SYMBOLS_TUPLE\" | cut -d' ' -f5`" == "GLOBAL" ] &&
       [ "`echo \"$SYMBOLS_TUPLE\" | cut -d' ' -f7`" != "UND" ];
    then
        FUNC_PAIR="`echo \"$SYMBOLS_TUPLE\" | cut -d' ' -f2,8 | sed 's/^0000000000400//g'`"
        FUNC_ADDR="`echo \"$FUNC_PAIR\" | cut -d' ' -f1`"
        FUNC_ADDR_DEC="`printf \"%d\" 0x$FUNC_ADDR`"
        FUNC_TRIPLE="$FUNC_ADDR_DEC $FUNC_PAIR"
        FUNC_TRIPLE_LIST="$FUNC_TRIPLE_LIST\n$FUNC_TRIPLE"
    fi
done < $SYMBOLS_FILE
if [ "$FOUND_SYMTAB" == 0 ]; then
    echo "Error: Can't find symtab section in \"$EXEC\"."
    exit
fi
FUNC_TRIPLE_LIST="`echo -e \"$FUNC_TRIPLE_LIST\" | sort | grep -v '^$'`"

echo "digraph `basename $EXEC` {"
echo "rankdir=LR;"
echo "node [shape=box];"
echo "_start"
echo "node [shape=ellipse];"

while read -r FUNC_TRIPLE; do
    FUNC_ADDR="`echo \"$FUNC_TRIPLE\" | cut -d' ' -f2`"
    FUNC_NAME="`echo \"$FUNC_TRIPLE\" | cut -d' ' -f3`"
    FUNC_NAME_DEMANGLED="`echo $FUNC_NAME | c++filt`"
    if [ "$FUNC_ADDR" == "$ENTRY_POINT_ADDR" ]; then
        SHAPE_SPEC_STR=", shape=\"box\""
    else
        SHAPE_SPEC_STR=""
    fi
    echo "$FUNC_NAME [label=\"0x$FUNC_ADDR: $FUNC_NAME_DEMANGLED\"$SHAPE_SPEC_STR];"
done <<< "$FUNC_TRIPLE_LIST"

i=1
while read -r FUNC_TRIPLE; do
    FUNC_ADDR="`echo \"$FUNC_TRIPLE\" | cut -d' ' -f2`"
    FUNC_NAME="`echo \"$FUNC_TRIPLE\" | cut -d' ' -f3`"

    FUNC_ASM_LINE_NO="`grep -n \"$FUNC_ADDR:\" $ASM_FILE | head -1 | cut -d':' -f1`"
    if [ -z "$FUNC_ASM_LINE_NO" ]; then
        i="`expr $i + 1`"
        continue
    fi

    NEXT_FUNC_INDEX="`expr $i + 1`"
    NEXT_FUNC_TRIPLE="`echo \"$FUNC_TRIPLE_LIST\" | head -$NEXT_FUNC_INDEX | tail -1`"

    NEXT_FUNC_ADDR="`echo \"$NEXT_FUNC_TRIPLE\" | cut -d' ' -f2`"
    NEXT_FUNC_NAME="`echo \"$NEXT_FUNC_TRIPLE\" | cut -d' ' -f3`"

    NEXT_FUNC_ASM_LINE_NO="`grep -n \"$NEXT_FUNC_ADDR:\" $ASM_FILE | head -1 | cut -d':' -f1`"
    FUNC_ASM_LAST_LINE_NO="`expr $NEXT_FUNC_ASM_LINE_NO - 1`"
    FUNC_ASM_BODY_LEN="`expr $NEXT_FUNC_ASM_LINE_NO - $FUNC_ASM_LINE_NO`"
    FUNC_ASM_BODY="`cat $ASM_FILE | head -$FUNC_ASM_LAST_LINE_NO | tail -$FUNC_ASM_BODY_LEN`"
    CALLEE_ASM_LINES_LIST="`echo \"$FUNC_ASM_BODY\" | grep 'callq'`"
    if [ -z "$CALLEE_ASM_LINES_LIST" ]; then
        i="`expr $i + 1`"
        continue
    fi

    while read -r CALLEE_ASM_LINE; do
        CALLEE_ADDR_PART="`echo \"$CALLEE_ASM_LINE\" | cut -d'	' -f1`"
        CALL_ADDR="`echo \"$CALLEE_ADDR_PART\" | cut -d':' -f1`"
        CALLEE_CMD="`echo \"$CALLEE_ASM_LINE\" | cut -d'	' -f3`"
        CALLEE_ADDR="`echo \"$CALLEE_CMD\" | sed 's/callq[ ]\+0x\([^ ]\+\)/\1/g'`"
        CALLEE_NAME="`echo \"$FUNC_TRIPLE_LIST\" | grep \"$CALLEE_ADDR\" | cut -d' ' -f3`"
        if [ -z "$CALLEE_NAME" ]; then
            continue
        fi
        echo "$FUNC_NAME -> $CALLEE_NAME [label=\"0x$CALL_ADDR\"]"
    done <<< "$CALLEE_ASM_LINES_LIST"

    i="`expr $i + 1`"
done <<< "$FUNC_TRIPLE_LIST"

echo "}"
