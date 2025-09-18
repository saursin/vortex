import readline
from vxdebug.utils import *
from vxdebug.backend import Backend, DMReg

DEBUGGER_HISTORY_FILE = ".vxdbg_history"
DEFAULT_DBGSERVER_PORT = 3333

class VortexDebugger:
    def __init__(self):
        self.backend = Backend()
        
        # CLI state
        self.cli_running = True
        self.commands = {}
        self.aliases = {}

        # Setup commands
        self.__setup_commands()

    def __register_command(self, name, alias=None, description="", func=None):
        if name in self.commands:
            raise ValueError(f"Command '{name}' is already registered.")
        self.commands[name] = {"descr": description, "function": func}
        if alias:
            if alias in self.aliases:
                raise ValueError(f"Alias '{alias}' is already registered.")
            self.aliases[alias] = name

    def connect_tcp(self, host=None, port=None, hostportstr=None):
        if hostportstr:
            host, port = parse_hostportstr(hostportstr, 'localhost', DEFAULT_DBGSERVER_PORT)
        self.backend.transport_setup("tcp")
        self.backend.transport_connect(host=host, port=port)
        self.backend.initialize()

    def run_cli(self):
        try:
            readline.read_history_file(DEBUGGER_HISTORY_FILE)
        except FileNotFoundError:
            pass

        def get_prompt():
            prompt = f'{ANSI_GRN}'
            # Add transport status
            prompt += '● ' if self.backend.transport_is_connected() else ''
            prompt += 'vxdbg '

            warp_selected = self.backend.get_selected_warp() is not None
            thread_selected = self.backend.get_selected_thread() is not None
            include_info_str = warp_selected and thread_selected
            
            if include_info_str:
                prompt += '['
                prompt += f'W{self.backend.get_selected_warp()}'
                prompt += f':T{self.backend.get_selected_thread()}'
                prompt += f', {ANSI_YLW}PC: 0x{self.backend.read_reg("pc"):08X}{ANSI_RST}'
                prompt += ']'

            prompt+= f'{ANSI_GRN}> {ANSI_RST}'
            return prompt

        try:
            while self.cli_running:
                try:
                    line = input(get_prompt()).strip()
                except EOFError:    # CTRL + D
                    print("")
                    break

                # remove comments prefixed with #
                line = line.split('#')[0].strip()
                if not line:
                    continue

                if line not in [readline.get_history_item(i) for i in range(1, readline.get_current_history_length() + 1)]:
                    readline.add_history(line)

                cmd = line.split()
                cmd_name = cmd[0]
                cmd_args = cmd[1:]

                # resolve alias if any
                if cmd_name in self.aliases:
                    cmd_name = self.aliases[cmd_name]


                if not cmd:
                    continue

                # Search command 
                if cmd_name in self.commands:
                    action = self.commands[cmd_name].get('function', None)
                    if action and callable(action):
                        try:
                            action(cmd_args)
                        except Exception as e:
                            Logger.error(f"Command '{cmd_name}' failed: {e}")  
                            # Print backtrace in debug mode
                            import traceback
                            traceback.print_exc()                     
                else:
                    Logger.warn(f"Unknown command: {cmd_name}")

        except KeyboardInterrupt: # Ctrl + C
            pass
        finally:
            try:
                readline.write_history_file(DEBUGGER_HISTORY_FILE)
            except Exception:
                pass

        self.backend.transport_disconnect()
        print("")  # New line after exiting
        Logger.info("Exiting... Goodbye!")

    def _run_script(self, script_path):
        try:
            Logger.info(f"Running script: {script_path}")
            with open(script_path, 'r') as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith('#'):
                        continue
                    print(f"{ANSI_YLW}>>> {line}{ANSI_RST}")
                    cmd = line.split()
                    cmd_name = cmd[0]
                    cmd_args = cmd[1:]

                    # resolve alias if any
                    if cmd_name in self.aliases:
                        cmd_name = self.aliases[cmd_name]

                    if cmd_name in self.commands:
                        action = self.commands[cmd_name].get('function', None)
                        if action and callable(action):
                            try:
                                action(cmd_args)
                            except Exception as e:
                                Logger.error(f"Command '{cmd_name}' failed: {e}")  
                                # Print backtrace in debug mode
                                import traceback
                                traceback.print_exc()                     
                    else:
                        Logger.warn(f"Unknown command: {cmd_name}")
                Logger.info(f"Finished running script: {script_path}")
        except FileNotFoundError:
            Logger.error(f"Script file not found: {script_path}")
        except Exception as e:
            Logger.error(f"Failed to run script '{script_path}': {e}")

    
    ############################################################################
    # Commands
    def _cmd_help(self, argv):
        parser = CmdArgumentParser(prog="help", description="Show help for commands")
        parser.add_argument("command", nargs="?", help="Command to show help for")
        args = parser.parse_args(argv)
        if not args:
            return
        
        if args.command:
            cmd_name = args.command
            cmd_name = self.aliases.get(cmd_name, cmd_name) # resolve alias if any

            if cmd_name in self.commands:
                cmd_fn = self.commands[cmd_name]['function']
                if cmd_fn:
                    cmd_fn(['--help'])
            else:
                Logger.warn(f"No help available for '{args.command}'")
        else:
            helpstr = ""
            for cmd_name, cmd_data in self.commands.items():
                cmd_alias = [alias for alias, name in self.aliases.items() if name == cmd_name]
                alias_str = f" ({', '.join(cmd_alias)})" if cmd_alias else ""
                tmpstr = f"{cmd_name}{alias_str}"

                helpstr += f"\t{tmpstr:25s}: {cmd_data['descr']}\n"
            Logger.info(f"Available commands:\n {helpstr}\n Try 'help <command>' for more details.")

    def _cmd_quit(self, argv):
        parser = CmdArgumentParser(prog="quit", description="Quit the debugger")
        args = parser.parse_args(argv)
        if args is None:
            return
        self.cli_running = False

    def _cmd_script(self, argv):
        parser = CmdArgumentParser(prog="script", description="Run a script file")
        parser.add_argument("script_path", help="Path to the script file")
        args = parser.parse_args(argv)
        if args is None:
            return
        self._run_script(args.script_path)

    def _cmd_transport(self, argv):
        parser = CmdArgumentParser(prog="transport", description="manage transport")
        parser.add_argument("-p", "--tcp", help="Connect via TCP (host:port)", type=str, default=None)
        parser.add_argument("-d", "--disconnect", help="Disconnect current transport", action="store_true")
        args = parser.parse_args(argv)
        if args is None:
            return
        
        if args.tcp:
            self.connect_tcp(hostportstr=args.tcp)
        elif args.disconnect:
            self.backend.transport_disconnect()
        else:
            Logger.error("No transport specified. e.g. Use --tcp to connect via TCP.")

    def _cmd_reset(self, argv):
        parser = CmdArgumentParser(prog="reset", description="Reset the backend connection")
        parser.add_argument("-H", "--halt", help="Halt warps after reset", action="store_true")
        args = parser.parse_args(argv)
        if args is None:
            return
        self.backend.reset_platform(halt_warps=args.halt)
        self.backend.initialize()

    def _cmd_info(self, argv):
        parser = CmdArgumentParser(prog="info", description="Show backend information")
        subparsers = parser.add_subparsers(dest="subcmd", help="Sub-commands")

        warps_parser = subparsers.add_parser("warps", help="Show warps information")

        args = parser.parse_args(argv)
        if args is None:
            return

        if args.subcmd == "warps":
            wstatus = self.backend.get_warp_status(get_pc=True)
            if wstatus is None:
                Logger.error("Failed to get warp status.")
                return
            wstatus_str = ""
            for wid, data in wstatus.items():
                status, pc = data['halted'], data['pc']
                coreid = wid // self.backend.plat_info['num_warps']
                local_wid = wid % self.backend.plat_info['num_warps']
                pcstr = f"0x{pc:08x}" if pc is not None else "N/A"
                wstatus_str += f"\tCore{coreid}-W{local_wid} (wid: {wid}): {'Halted' if status else 'Running'} (PC: {pcstr})\n"
            Logger.info(f"Warps status:\n{wstatus_str}")
        else:
            self.backend._print_platform_info()
        
    def _cmd_halt(self, argv):
        parser = CmdArgumentParser(prog="halt", description="Halt warps")
        parser.add_argument("warp_ids", nargs="+", type=int, help="Warp IDs to halt")
        args = parser.parse_args(argv)
        if args is None:
            return
        self.backend.halt_warps(args.warp_ids)
        if self.backend.all_halted():
            Logger.info("All warps are halted.")
        elif self.backend.any_halted():
            Logger.info("Some warps are halted.")
        else:
            Logger.warn("No warps are halted.")

    def _cmd_continue(self, argv):
        parser = CmdArgumentParser(prog="continue", description="Continue warp execution")
        parser.add_argument("warp_ids", nargs="+", type=int, help="Warp IDs to continue")
        args = parser.parse_args(argv)
        if args is None:
            return
        self.backend.resume_warps(args.warp_ids)
        if self.backend.any_halted():
            Logger.info("Some warps are still halted.")
        else:
            Logger.info("All warps are running.")

    def _cmd_select(self, argv):
        parser = CmdArgumentParser(prog="select", description="Manage warps")
        parser.add_argument("wid", type=int, nargs="?", default=0, help="Warp ID to select")
        parser.add_argument("tid", type=int, nargs="?", default=0, help="Thread ID to select")
        args = parser.parse_args(argv)
        if args is None:
            return
        if 0 <= args.wid < self.backend.plat_info['num_total_warps']:
            self.backend.select_a_warp(args.wid)
            Logger.info(f"Selected warp ID set to {args.wid}")
        else:
            Logger.error(f"Warp ID {args.wid} is out of range (0-{self.backend.plat_info['num_total_warps']-1})")
            return
        if 0 <= args.tid < self.backend.plat_info['num_threads']:
            self.backend.select_a_thread(args.tid)
            Logger.info(f"Selected thread ID set to {args.tid}")
        else:
            Logger.error(f"Thread ID {args.tid} is out of range (0-{self.backend.plat_info['num_threads']-1})")
            return

    def _cmd_stepi(self, argv):
        parser = CmdArgumentParser(prog="stepi", description="Single step the selected warp")
        args = parser.parse_args(argv)
        if args is None:
            return
        selected_wid = self.backend.get_selected_warp()
        if selected_wid is None:
            Logger.error("No warp selected. Use 'select <id>' to select a warp.")
            return       
        self.backend.step_warp()
        if self.backend.selected_warp_pc is not None:
            Logger.info(f"Warp {selected_wid} stepped to PC=0x{self.backend.selected_warp_pc:X}")


    def _cmd_dmreg(self, argv):
        parser = CmdArgumentParser(prog="dmreg", description="DM Register operations")
        subparsers = parser.add_subparsers(dest="subcmd", help="Sub-commands")

        read_parser = subparsers.add_parser("read", help="Read DM registers")
        read_parser.add_argument("names", nargs="+", help="DM Register names to read (e.g. DMSTATUS, HALTREQ)")

        write_parser = subparsers.add_parser("write", help="Write DM registers")
        write_parser.add_argument("name", help="DM Register name to write (e.g. DMCONTROL, HALTREQ)")
        write_parser.add_argument("value", help="Value to write (in hex or decimal)")
        write_parser.add_argument("-f", "--field", help="Field name to write (e.g. haltreq, resumereq)", default=None)

        args = parser.parse_args(argv)
        if args is None:
            return

        if args.subcmd == "read":
            for name in args.names:
                reg = self.backend._get_dmreg_by_name(name)
                if reg is None:
                    Logger.error(f"Unknown DM register: {name}")
                    continue
                self.backend._print_dmreg(reg)
        elif args.subcmd == "write":
            reg = self.backend._get_dmreg_by_name(args.name)
            if reg is None:
                Logger.error(f"Unknown DM register: {args.name}")
                return
            value = str2int(args.value)
            if args.field:
                success = self.backend._dmreg_write(reg, value, args.field)
            else:
                success = self.backend._dmreg_write(reg, value)
            if success:
                Logger.info(f"Wrote 0x{value:X} to DM register {reg.name}{'.'+args.field if args.field else ''}.")
            else:
                Logger.error(f"Failed to write to DM register {reg.name}{'.'+args.field if args.field else ''}.")
        else:
            parser.print_help()


    def _cmd_reg(self, argv):
        parser = CmdArgumentParser(prog="reg", description="Register operations")
        subparsers = parser.add_subparsers(dest="subcmd", help="Sub-commands")

        read_parser = subparsers.add_parser("read", help="Read registers")
        read_parser.add_argument("names", nargs="+", help="Register names to read (e.g. pc, sp, x3)")

        write_parser = subparsers.add_parser("write", help="Write registers")
        write_parser.add_argument("name", help="Register name to write (e.g. pc, sp, x3)")
        write_parser.add_argument("value", help="Value to write (in hex or decimal)")

        args = parser.parse_args(argv)
        if args is None:
            return

        if args.subcmd == "read":
            regvals = self.backend.read_regs(args.names)
            regstr = ""
            for regname, val in regvals.items():
                if val is not None:
                    regstr += f"{regname}: 0x{val:08x}\n"
            Logger.info(f"Registers:\n{regstr}")
        elif args.subcmd == "write":
            value = str2int(args.value)
            success = self.backend.write_reg(args.name, value)
            if success:
                Logger.info(f"Wrote 0x{value:08x} to register {args.name}.")
            else:
                Logger.error(f"Failed to write to register {args.name}.")
        else:
            parser.print_help()


    def _cmd_mem(self, argv):
        parser = CmdArgumentParser(prog="mem", description="Memory operations")
        subparsers = parser.add_subparsers(dest="subcmd", help="Sub-commands")

        read_parser = subparsers.add_parser("read", help="Read memory")
        read_parser.add_argument("address", help="Start address to read from")
        read_parser.add_argument("length", help="Number of bytes to read")

        write_parser = subparsers.add_parser("write", help="Write memory")
        write_parser.add_argument("address", help="Start address to write to")
        write_parser.add_argument("data", nargs="+", help="Data bytes to write (in hex or decimal)")

        args = parser.parse_args(argv)
        if args is None:
            return

        if args.subcmd == "read":
            addr = str2int(args.address)
            length = str2int(args.length)
            data = self.backend.read_mem(addr, length)
            if data is not None:
                hexstr = hexdump(data, base_addr=addr)
                Logger.info(f"Memory at 0x{addr:08x} ({length} bytes):\n{hexstr}")
            else:
                Logger.error("Failed to read memory.")
        elif args.subcmd == "write":
            addr = str2int(args.address)
            data = [str2int(x) & 0xFF for x in args.data]
            success = self.backend.write_mem(addr, data)
            if success:
                Logger.info(f"Wrote {len(data)} bytes to 0x{addr:08x}.")
            else:
                Logger.error("Failed to write memory.")
        else:
            parser.print_help()

    
    def __setup_commands(self):
        self.__register_command("help", alias="H", description="Show this help message", func=self._cmd_help)
        self.__register_command("quit", alias="q", description="Quit the debugger", func=self._cmd_quit)
        self.__register_command("transport", alias="T", description="Manage transport connection", func=self._cmd_transport)
        self.__register_command("script", alias="S", description="Run a script file", func=self._cmd_script)
        self.__register_command("reset", alias="R", description="Reset the device", func=self._cmd_reset)
        self.__register_command("info", alias="i", description="Show information", func=self._cmd_info)
        self.__register_command("halt", alias="h", description="Halt warps", func=self._cmd_halt)
        self.__register_command("continue", alias="c", description="Continue warps", func=self._cmd_continue)
        self.__register_command("select", alias="sel", description="Select current warp and thread", func=self._cmd_select)
        self.__register_command("stepi", alias="s", description="Single step the selected warp", func=self._cmd_stepi)
        self.__register_command("dmreg", alias="d", description="DM Register operations", func=self._cmd_dmreg)
        self.__register_command("reg", alias="r", description="Register operations", func=self._cmd_reg)
        self.__register_command("mem", alias="m", description="Memory operations", func=self._cmd_mem)
