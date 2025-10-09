#pragma once
#include <atomic>
#include <functional>
#include <string>
#include <thread>

#pragma once
#include <atomic>
#include <functional>
#include <string>
#include <thread>

// Minimal threaded TCP debug server for register access
class DebugServer {
public:
  struct Callbacks {
    std::function<int(uint32_t addr, uint32_t* val)> on_read_reg;
    std::function<int(uint32_t addr, uint32_t val)> on_write_reg;
  };

  DebugServer();
  ~DebugServer();

  // Start server in background
  void start(int port, Callbacks cb);

  // Wait until a client connects (blocking)
  bool wait_for_client(int timeout_ms = -1);

  // Return true if connected
  bool is_connected() const { return connected_.load(); }

private:
  void server_loop(int port);

  std::atomic<bool> running_{false};
  std::atomic<bool> connected_{false};
  Callbacks cb_;
  std::thread server_thread_;
};
