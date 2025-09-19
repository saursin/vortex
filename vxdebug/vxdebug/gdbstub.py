import socket
import re
from vxdebug.backend import Backend
from vxdebug.utils import Logger

# -----------------------------------------------------------------------------
# Utility helpers
# -----------------------------------------------------------------------------

def checksum_str(msg: str) -> str:
    return "{:02x}".format(sum(ord(c) for c in msg) & 0xff)

def packetify(msg: str) -> str:
    return f"${msg}#{checksum_str(msg)}"

# -----------------------------------------------------------------------------
# GdbStub
# -----------------------------------------------------------------------------

class GDBStub:
    def __init__(self, backend: Backend, port=3333):
        self.backend = backend
        self.port = port
        self.sock = None
        self.client = None
        self.bp_set = set()
        self.is_attached = False

        self.log = Logger("GDBStub")


        # Map commands to handlers
        self.cmd_map = {
            "?": self.cmd_halted,
            "D": self.cmd_detach,
            "g": self.cmd_read_regs,
            "G": self.cmd_write_regs,
            "p": self.cmd_read_reg,
            "P": self.cmd_write_reg,
            "m": self.cmd_read_mem,
            "M": self.cmd_write_mem,
            "c": self.cmd_continue,
            "s": self.cmd_step,
            "Z": self.cmd_insert_bp,
            "z": self.cmd_remove_bp,
            "k": self.cmd_kill,
            "qSupported": self.cmd_supported,
            "qAttached": self.cmd_attached,
            "vMustReplyEmpty": self.cmd_notfound        # Should behave same as any other unknown command
        }

    # -------------------------------------------------------------------------
    # Connection
    # -------------------------------------------------------------------------
    def start(self):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(("0.0.0.0", self.port))
        self.sock.listen(1)
        self.log.info(f"Waiting for GDB on port {self.port}...")
        self.client, addr = self.sock.accept()
        self.log.info(f"GDB connected from {addr}")

    def recv_packet(self) -> str:
        buf = ""
        # Get first char
        ch = self.client.recv(1).decode("ascii")
        if not ch:
            self.log.info("GDB disconnected.")
            return ""   # Connection closed

        buf += ch
        if buf[0] == "+":
            self.log.debug("Got: ACK (+)")
            return None 
        if buf[0] == "-":
            self.log.debug("Got: NACK (-)")
            return None
        if buf[0] == "\x03":
            self.log.debug("Got: Ctrl-C, sending SIGTRAP")
            self.cmd_halted([])
            return None
        if buf[0] != "$":
            self.log.warn(f"ERROR: Got msg not beginning with `$`: {buf[0]}")
            return None
        
        calculated_checksum = 0
        while True:
            c = self.client.recv(1).decode("ascii")
            if not c:
                self.log.info("GDB disconnected.")
                return ""   # Connection closed
            buf += c
            calculated_checksum += ord(c)
            if len(buf) > 4096:
                self.log.warn(f"ERROR: Packet too long: {buf}")
                return ""   # Connection closed
            if c == "#":
                break

        calculated_checksum -= ord("#")
        got_checksum_str = self.client.recv(2).decode("ascii", errors="ignore")
        got_checksum = int(got_checksum_str, 16)
        buf += got_checksum_str
        self.log.debug(f"Got: {buf}")

        if (calculated_checksum & 0xff) != got_checksum:
            self.log.warn(f"ERROR: Bad checksum, calculated {calculated_checksum & 0xff:02x}, got {got_checksum:02x}")
        return buf

    def send_packet(self, msg: str):
        if msg is None:
                msg = ""   # must respond empty
        pkt = packetify(msg)
        try:
            self.client.sendall(pkt.encode("ascii"))
            self.log.debug(f"Snt: {pkt}")
        except BrokenPipeError:
            self.log.info("GDB disconnected: Broken pipe.")
            self.client = None

    def send_ack(self):
        self.client.sendall(b"+")
        self.log.debug("Snt: ACK (+)")

    def serve_forever(self):
        self.start()
        while True:
            pkt = self.recv_packet()
            if pkt is None:
                continue
            cmdstr = pkt[1:-3]  # strip $ and #xx
            for cmd, callback in self.cmd_map.items():
                if cmdstr.startswith(cmd):
                    self.send_ack()
                    callback(cmdstr)
                    break
            else:
                self.send_ack()
                self.cmd_notfound(cmdstr)


    # -------------------------------------------------------------------------
    # Command Handlers
    # See: https://sourceware.org/gdb/current/onlinedocs/gdb.html/General-Query-Packets.html
    # -------------------------------------------------------------------------

    # cmd: qSupported [:gdbfeature [;gdbfeature]... ]
    # desc: Advertise and request for supported features
    # reply: ‘PacketSize=xxxx[;gdbfeature[;gdbfeature]...]’
    def cmd_supported(self, cmdstr):
        args = cmdstr[len("qSupported"):].split(";")
        rsp = "PacketSize=4096;"
        if "hwbreak+" in args:
            rsp += "hwbreak+;"
        self.send_packet(rsp)

    # cmd: qAttached:pid
    # desc: Check if the remote server is attached to a running program
    # reply: '1' if attached to running program, '0' if started by gdb
    def cmd_attached(self, cmdstr):
        self.send_packet("1")   # Remote server is attached to a running program
        self.is_attached = True

    # cmd: ?
    # desc: Query the reason behind the target halt
    # Reply: Signal that caused the target to stop
    def cmd_halted(self, cmdstr):
        self.backend.halt_warps()
        self.send_packet("S05")  # SIGTRAP

    # cmd: D:pid
    # desc: Detach the remote server from the target
    # reply: OK if successful
    def cmd_detach(self, cmdstr):
        self.is_attached = False
        self.backend.resume_warps()  # continue
        self.send_packet("OK")

    # cmd: g 
    # Read general registers
    # reply: xxx... (concatenated register values, target dependent format)
    def cmd_read_regs(self, cmdstr):
        regs = ""
        # Get all 32 GPRs
        for i in range(32):
            val = self.backend.read_reg(f"x{i}") or 0
            regs += int(val).to_bytes(4, "little").hex()
        # Get PC
        pc = self.backend.read_reg("pc") or 0
        regs += int(pc).to_bytes(4, "little").hex()
        self.send_packet(regs)

    # cmd: G xxx...
    # desc: Write general registers
    # reply: OK if successful
    def cmd_write_regs(self, cmdstr):
        reg_data = bytes.fromhex(cmdstr[1:])
        # Write all 32 GPRs
        for i in range(32):
            val = int.from_bytes(reg_data[i*4:(i+1)*4], "little")
            self.backend.write_reg(f"x{i}", val)
        # Write PC
        pc = int.from_bytes(reg_data[32*4:33*4], "little")
        self.backend.write_reg("pc", pc)
        self.send_packet("OK")

    # cmd: p reg_idx
    # desc: Read a single register
    # reply: xxxx...
    def cmd_read_reg(self, cmdstr):
        reg_num = int(cmdstr[1:], 16)
        if 0 <= reg_num < 32:
            val = self.backend.read_reg(f"x{reg_num}")
        elif reg_num == 32:
            val = self.backend.read_reg("pc")
        else:
            val = None
        
        if val is None:
            self.send_packet("E02")  # Error reading register
        else:
            self.send_packet(int(val).to_bytes(4, "little").hex())

    # cmd: P reg_idx=val
    # desc: Write a single register
    # reply: OK if successful
    def cmd_write_reg(self, cmdstr):
        reg_id, val_str = cmdstr[1:].split("=")
        reg_num = int(reg_id, 16)
        val = int(val_str, 16)
        success = False
        if 0 <= reg_num < 32:
            success = self.backend.write_reg(f"x{reg_num}", val)
        elif reg_num == 32:
            success = self.backend.write_reg("pc", val)
        self.send_packet("OK" if success else "E01")
    
    # cmd: m addr,length
    # desc: Read memory
    # reply: xx... (binary data as a sequence of hex digits)
    def cmd_read_mem(self, cmdstr):
        addr, len = cmdstr[1:].split(",")
        addr = int(addr, 16)
        len = int(len, 16)
        data = self.backend.read_mem(addr, len)
        if data is None:
            self.send_packet("E01")
        else:
            self.send_packet(data.hex())

    # cmd: M addr,length:xx...
    # desc: Write memory
    # reply: OK if successful
    def cmd_write_mem(self, cmdstr):
        addr, len, data = re.split(r'[:,]', cmdstr[1:])
        addr = int(addr, 16)
        len = int(len, 16)
        data = bytes.fromhex(data)
        success = self.backend.write_mem(addr, data)
        self.send_packet("OK" if success else "E02")

    # cmd: c [addr]
    # desc: Continue execution, optionally from address addr
    # reply: Sxx (signal that caused the target to stop)
    def cmd_continue(self, cmdstr):
        if len(cmdstr) > 1:
            addr = int(cmdstr[1:], 16)
            self.backend.write_reg("pc", addr)
        
        if len(self.backend.get_breakpoints()) > 0:
            self.backend.continue_until_break()
        else:
            self.backend.resume_warps()
        self.send_packet("S05")  # SIGTRAP

    # cmd: s [addr]
    # desc: Step execution, optionally from address addr
    # reply: Sxx (signal that caused the target to stop)
    def cmd_step(self, cmdstr):
        if len(cmdstr) > 1:
            addr = int(cmdstr[1:], 16)
            self.backend.write_reg("pc", addr)
        self.backend.step_warp()
        self.send_packet("S05")  # SIGTRAP

    # cmd: Z type,addr,kind
    # desc: Insert breakpoint/watchpoint
    # reply: OK if successful
    def cmd_insert_bp(self, cmdstr):
        bptype, addr, kind = cmdstr[1:].split(",")
        addr = int(addr, 16)
        kind = int(kind, 16)
        if bptype == "0" or bptype == "1":      # Sw/Hw breakpoint
            self.backend.set_breakpoint(addr)
            self.send_packet("OK")
        else:
            self.log.warn(f"Unsupported breakpoint type: {bptype}, kind: {kind}")

    # cmd: z type,addr,kind
    # desc: Remove breakpoint/watchpoint
    # reply: OK if successful
    def cmd_remove_bp(self, cmdstr):
        bptype, addr, kind = cmdstr[1:].split(",")
        addr = int(addr, 16)
        kind = int(kind, 16)
        if bptype == "0" or bptype == "1":      # Sw/Hw breakpoint
            self.backend.delete_breakpoint(addr)
            self.send_packet("OK")
        else:
            self.log.warn(f"Unsupported breakpoint type: {bptype}, kind: {kind}")
        self.send_packet("OK")

    # cmd: k
    # desc: Kill the target
    # reply: None
    def cmd_kill(self, cmdstr):
        self.backend.reset()
        self.send_packet("")   # Empty response
    
    # All other commands
    def cmd_notfound(self, cmdstr):
        self.log.debug(f"Unknown Command: {cmdstr}, Skipping...")
        self.send_packet("")   # Empty response for unknown commands

    