//
//  miscellaneous.m
//  xref
//
//  Created by Derek Selander on 3/7/19.
//  Copyright © 2019 Selander. All rights reserved.
//

#import "miscellaneous.h"
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>

BOOL quiet_mode = NO;
NSMutableSet <NSString*> *pathsSet = nil;
NSMutableSet <NSString*> *exploredSet = nil;
NSMutableSet <NSString*> *rpathSet = nil;

xref_options_t xref_options;

__attribute__((constructor)) static void InitializeStuff() {
    pathsSet = [NSMutableSet set];
    exploredSet = [NSMutableSet set];
    rpathSet = [NSMutableSet set];
}

/********************************************************************************
 //  Documentation
 ********************************************************************************/
static const char * dsdump_usage = "dsdump [option..] <mach-o-file>";

void print_manpage() {
    printf("%s\n\n", __manpage_deets ? (const char*)&__manpage_deets : dsdump_usage);
}

void print_usage() {
    printf("Version: 0.1.0, Built: (%s, %s) %s\n", __TIME__, __DATE__, dsdump_usage);
}

/********************************************************************************
 //  Colors!
 ********************************************************************************/

char* dcolor(DSCOLOR c) {
    static BOOL useColor = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (xref_options.color || getenv("DSCOLOR")) {
            useColor = YES;
        }
    });
    if (!useColor) {
        return "";
    }
    
    switch (c) {
        case DSCOLOR_CYAN:
            return "\e[36m";
        case DSCOLOR_GREEN:
            return "\e[92m";
        case DSCOLOR_YELLOW:
             return "\e[33m";
        case DSCOLOR_MAGENTA:
            return "\e[95m";
        case DSCOLOR_PURPLE:
            return "\e[35m";
        case DSCOLOR_RED:
            return "\e[91m";
        case DSCOLOR_BLUE:
            return "\e[34m";
        case DSCOLOR_GRAY:
            return "\e[90m";
        case DSCOLOR_BOLD:
             return "\e[1m";
        case DSCOLOR_CYANISH:
            return "\033[36;1;4m";
        default:
            return "";
    }
}

char *color_end() {
    static BOOL useColor = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (xref_options.color || getenv("DSCOLOR")) {
            useColor = YES;
        }
    });
    if (useColor) {
        return "\e[0m";
    }
    return "";
}

void warn_debug(const char *format, ...) {
    if (!xref_options.debug) {
        return;
    }
    va_list args;
    va_start( args, format );
    dprintf(STDERR_FILENO, format, args );
    va_end( args );
}

/********************************************************************************
 //  Leb128 Encoding
 ********************************************************************************/

/* Read a ULEB128 into a 64-bit word.  Return (uint64_t)-1 on overflow
 or error.  On overflow, skip past the rest of the uleb128.  */
uint64_t read_uleb128 (const uint8_t ** offset, const uint8_t * end) {
    uint64_t result = 0;
    int bit = 0;
    
    do  {
        uint64_t b;
        
        if (*offset == end)
            return (uint64_t) -1;
        
        b = **offset & 0x7f;
        
        if (bit >= 64 || b << bit >> bit != b) {
            result = (uint64_t) -1;
        } else {
            result |= b << bit;
            bit += 7;
        }
    } while (*(*offset)++ >= 0x80);
    return result;
}

/// Unsigned Leb128
const uint8_t *r_uleb128_decode(uint8_t *data, int *datalen, uint64_t *v) {
    uint8_t c = 0xff;
    uint64_t s = 0, sum = 0, l = 0;
    if (data && *data) {
        do {
            c = *(data++) & 0xff;
            sum |= ((uint64_t) (c & 0x7f) << s);
            s += 7;
            l++;
        } while (c & 0x80);
    }
    if (v)  {*v = sum; }
    if (datalen) { *datalen = (int)l; }
    return data;
}

/// Signed Leb128
const uintptr_t r_sleb128_decode(uint8_t *byte, uintptr_t* datalen, uint64_t *v) {
    uintptr_t result = 0;
    uintptr_t shift = 0;
    
    size_t size = sizeof(signed int);
    uint8_t *cur = byte;
    int l =0 ;
    do{
        l++;
        result |= ((0x7f & *cur) << shift);
        shift += 7;
    } while((*cur & 0x80) != 0);
    
    /* sign bit of byte is second high order bit (0x40) */
    if ((shift < size) && (*cur & 0x80)) {
        /* sign extend */
        result |= (~0 << shift);
    }
    
    if (v) { *v = result; }
    if (datalen) { *datalen = l; }
    return result;
}
