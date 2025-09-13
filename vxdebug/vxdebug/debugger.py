import readline
from vxdebug.utils import *
from vxdebug.backend import Backend

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
            prompt += '● ' if self.backend.transport_is_connected() else ''
            prompt += f'vxdbg'
            prompt += f' [W {self.backend._get_selected_warp()}]' if self.backend._get_selected_warp() is not None else ''
            prompt+= f'{ANSI_RST}> '
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

    def _cmd_transport(self, argv):
        parser = CmdArgumentParser(prog="transport", description="manage transport")
        parser.add_argument("-p", "--tcp", help="Connect via TCP (host:port)", type=str, default=None)
        parser.add_argument("--disconnect", help="Disconnect current transport", action="store_true")
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
        args = parser.parse_args(argv)
        if args is None:
            return
        self.backend._reset_platform()
        self.backend.initialize()

    def _cmd_info(self, argv):
        parser = CmdArgumentParser(prog="info", description="Show backend information")
        subparsers = parser.add_subparsers(dest="subcmd", help="Sub-commands")
        
        dmreg_parser = subparsers.add_parser("dmreg", help="Show DM register values")
        dmreg_parser.add_argument("reg", nargs="?", help="Register to show (e.g. WINSEL)")

        warps_parser = subparsers.add_parser("warps", help="Show warps information")

        args = parser.parse_args(argv)
        if args is None:
            return

        if args.subcmd == "dmreg":
            if args.reg:
                reg = self.backend._get_dmreg_by_name(args.reg)
                val = self.backend.reg_read(reg)
                Logger.info(f"{reg} (0x{reg.value.addr:02x}): 0x{val:08x}")           
        if args.subcmd == "warps":
            wstatus = self.backend._get_warp_status()
            if wstatus is None:
                Logger.error("Failed to get warp status.")
                return
            wstatus_str = ""
            for wid, (status, pc) in wstatus.items():
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
        self.backend._halt_warps(args.warp_ids)
        if self.backend._any_halted():
            Logger.info("Some warps are halted.")
        else:
            Logger.warn("No warps are halted.")

    def _cmd_continue(self, argv):
        parser = CmdArgumentParser(prog="continue", description="Continue warp execution")
        parser.add_argument("warp_ids", nargs="+", type=int, help="Warp IDs to continue")
        args = parser.parse_args(argv)
        if args is None:
            return
        self.backend._resume_warps(args.warp_ids)
        if self.backend._any_halted():
            Logger.info("Some warps are still halted.")
        else:
            Logger.info("All warps are running.")

    def _cmd_warp(self, argv):
        parser = CmdArgumentParser(prog="warp", description="Manage warps")
        parser.add_argument("id", nargs="?", type=int, help="Warp ID to select")
        args = parser.parse_args(argv)
        if args is None:
            return
        if args.id is not None:
            if 0 <= args.id < self.backend.plat_info['num_total_warps']:
                self.backend._select_a_warp(args.id)
                Logger.info(f"Selected warp ID set to {args.id}")
            else:
                Logger.error(f"Warp ID {args.id} is out of range (0-{self.backend.plat_info['num_total_warps']-1})")
        else:
            Logger.info(f"Current selected warp ID: {self.backend._get_selected_warp()}")

    def _cmd_stepi(self, argv):
        parser = CmdArgumentParser(prog="stepi", description="Single step the selected warp")
        args = parser.parse_args(argv)
        if args is None:
            return
        selected_wid = self.backend._get_selected_warp()
        if selected_wid is None:
            Logger.error("No warp selected. Use 'warp <id>' to select a warp.")
            return       
        self.backend._step_warp()
        if self.backend.selected_warp_pc is not None:
            Logger.info(f"Warp {selected_wid} stepped to PC=0x{self.backend.selected_warp_pc:X}")

    
    def __setup_commands(self):
        self.__register_command("help", alias=None, description="Show this help message", func=self._cmd_help)
        self.__register_command("quit", alias="q", description="Quit the debugger", func=self._cmd_quit)
        self.__register_command("transport", alias="t", description="Manage transport connection", func=self._cmd_transport)
        self.__register_command("reset", alias="r", description="Reset the device", func=self._cmd_reset)
        self.__register_command("info", alias="i", description="Show information", func=self._cmd_info)
        self.__register_command("halt", alias="h", description="Halt warps", func=self._cmd_halt)
        self.__register_command("continue", alias="c", description="Continue warps", func=self._cmd_continue)
        self.__register_command("warp", alias="w", description="Select or show current warp", func=self._cmd_warp)
        self.__register_command("stepi", alias="s", description="Single step the selected warp", func=self._cmd_stepi)
