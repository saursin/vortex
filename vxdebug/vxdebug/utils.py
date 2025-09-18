import argparse
import sys
import time
from contextlib import contextmanager

ANSI_BLU = "\033[94m"
ANSI_GRN = "\033[92m"
ANSI_YLW = "\033[93m"
ANSI_RED = "\033[91m"
ANSI_CYN = "\033[96m"
ANSI_RST = "\033[0m"
ANSI_GRY = "\033[90m"

# ANSI colors
ANSI_RST = "\033[0m"
ANSI_GRY = "\033[90m"
ANSI_CYN = "\033[36m"
ANSI_YLW = "\033[33m"
ANSI_RED = "\033[31m"


class _LogMethod:
    def __init__(self, level, color, tag):
        self.level = level
        self.color = color
        self.tag = tag

    def __get__(self, obj, objtype=None):
        def wrapper(*args, **kwargs):
            # Decide verbosity
            verbosity = getattr(obj, "verbosity", None)
            if verbosity is None:
                verbosity = objtype.verbosity

            # Decide threshold (only matters for debug)
            debug_threshold = getattr(obj, "debug_threshold", objtype.debug_threshold)

            # Prefix
            prefix = ""
            if obj and obj.prefix:
                prefix = f"({obj.prefix}) "
            elif not obj and objtype._global_prefix:
                prefix = f"({objtype._global_prefix}) "

            if self.level == 3:  # debug
                call_thr = kwargs.pop("threshold", 3)
                if verbosity >= call_thr and call_thr >= debug_threshold:
                    print(f"{self.color}{prefix}{self.tag}", *args, end=ANSI_RST+"\n")
            else:
                if verbosity >= self.level:
                    print(f"{self.color}{prefix}{self.tag}{ANSI_RST}", *args)
        return wrapper


class Logger:
    verbosity = 2
    debug_threshold = 3
    _global_prefix = ""

    def __init__(self, prefix="", verbosity=None, debug_threshold=None):
        self.prefix = prefix
        self.verbosity = verbosity
        self.debug_threshold = debug_threshold if debug_threshold is not None else Logger.debug_threshold

    @classmethod
    def set_prefix(cls, prefix):
        cls._global_prefix = prefix

    @classmethod
    def set_verbosity(cls, level):
        cls.verbosity = level

    @classmethod
    def set_debug_threshold(cls, thr):
        cls.debug_threshold = thr

    # Methods
    debug = _LogMethod(3, ANSI_GRY, "[>]")
    info  = _LogMethod(2, ANSI_CYN, "[+]")
    warn  = _LogMethod(1, ANSI_YLW, "[!]")
    error = _LogMethod(0, ANSI_RED, "[ERROR]")




class CmdArgumentParser(argparse.ArgumentParser):
    def exit(self, status=0, message=None):
        # Don't terminate the program
        if message:
            self._print_message(message, sys.stderr)

    def error(self, message):
        # Don't exit on parsing errors either
        self._print_message(f"error: {message}\n", sys.stderr)

    # Override parse_args to return True on help request
    def parse_args(self, args=None, namespace=None):
        if args is None:
            raise ValueError("args cannot be None")
        
        help_requested = '-h' in args or '--help' in args
        if help_requested:
            self.print_help()
            return None
        return super().parse_args(args, namespace)
    

def genmask(hi, lo):
    return ((1 << (hi - lo + 1)) - 1) << lo

def getbits(value, hi, lo):
    mask = (1 << (hi - lo + 1)) - 1
    return (value >> lo) & mask

def setbits(orig, hi, lo, value):
    mask = (1 << (hi - lo + 1)) - 1
    orig &= ~(mask << lo)
    orig |= (value & mask) << lo
    return orig

def str2int(s):
    try:
        if s.startswith("0x") or s.startswith("0X"):
            return int(s, 16)
        elif s.startswith("0b") or s.startswith("0B"):
            return int(s, 2)
        else:
            return int(s, 10)
    except ValueError:
        raise argparse.ArgumentTypeError(f"Invalid integer value: {s}")

# def hexdump(data, base_addr=0, words_per_line=4, bytes_per_word=4):
#     if not data:
#         return "<empty>"
#     lines = []
#     total_bytes = len(data)
#     bytes_per_line = words_per_line * bytes_per_word
#     for i in range(0, total_bytes, bytes_per_line):
#         chunk = data[i:i+bytes_per_line]
#         hex_bytes = ' '.join(f"{b:02x}" for b in chunk)
#         ascii_bytes = ''.join((chr(b) if 32 <= b < 127 else '.') for b in chunk)
#         line_addr = base_addr + i
#         lines.append(f"{line_addr:08x}  {hex_bytes:<{bytes_per_line*3}}  |{ascii_bytes}|")
#     return '\n'.join(lines)
import string

def hexdump(data: bytes,
        base_addr: int = 0,
        words_per_line: int = 4,
        bytes_per_word: int = 4,
        ascii_view: bool = True,
        show_offset: bool = True,
        upper_case: bool = True) -> str:
    """
    Pretty-print a hex dump of binary data.

    Args:
        data (bytes): Data to dump.
        base_addr (int): Starting address (printed at left).
        words_per_line (int): How many words per line.
        bytes_per_word (int): How many bytes per word.
        ascii_view (bool): Whether to show ASCII view on right.
        show_offset (bool): Whether to show base+offset at line start.
        upper_case (bool): Upper-case hex (vs lower-case).

    Returns:
        str: Formatted hex dump.
    """
    hex_fmt = f"{{:0{bytes_per_word*2}{'X' if upper_case else 'x'}}}"
    ascii_printable = string.ascii_letters + string.digits + string.punctuation + " "

    lines = []
    for offset in range(0, len(data), words_per_line * bytes_per_word):
        chunk = data[offset:offset + words_per_line * bytes_per_word]

        # left addr
        if show_offset:
            line = f"{base_addr + offset:08X}  "
        else:
            line = ""

        # hex words
        words = []
        for w in range(0, len(chunk), bytes_per_word):
            word = chunk[w:w + bytes_per_word]
            val = int.from_bytes(word, "little")
            words.append(hex_fmt.format(val))
        line += " ".join(words)

        # padding if last line short
        if len(chunk) < words_per_line * bytes_per_word:
            missing = words_per_line - len(words)
            if missing > 0:
                line += " " * ((bytes_per_word * 2 + 1) * missing)

        # ascii view
        if ascii_view:
            ascii_str = "".join(chr(b) if chr(b) in ascii_printable else "." for b in chunk)
            line += "  |" + ascii_str.ljust(words_per_line * bytes_per_word, ".") + "|"

        lines.append(line)

    return "\n".join(lines)



class TimeoutError(Exception):
    pass

@contextmanager
def timeout(seconds, message="Timeout expired"):
    """Context manager for enforcing timeouts."""
    start = time.monotonic()
    yield
    elapsed = time.monotonic() - start
    if elapsed > seconds:
        Logger.error(f"{message} (>{seconds}s, elapsed {elapsed:.2f}s)")
        


def parse_hostportstr(s, default_host='localhost', default_port=3333):
    try:
        if ":" in s:
            host, port = s.split(":")
            host = host if host else default_host
            port = int(port) if port else default_port
        else:
            host, port = default_host, int(s)
    except ValueError:
        Logger.error("Invalid TCP argument. Use format host:port or port.")
        return
    return host, port