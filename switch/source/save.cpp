#include "save.hpp"

#include <cstdlib>
#include <fstream>
#include <sys/stat.h>

Save& Save::get() {
  static Save s;
  return s;
}

Save::Save() {
#ifdef __SWITCH__
  mkdir("sdmc:/switch", 0777);
  mkdir("sdmc:/switch/mobilegames", 0777);
  path_ = "sdmc:/switch/mobilegames/save.txt";
#else
  path_ = "mobilegames_save.txt";
#endif
  std::ifstream in(path_);
  std::string line;
  while (std::getline(in, line)) {
    const auto eq = line.find('=');
    if (eq != std::string::npos) values_[line.substr(0, eq)] = line.substr(eq + 1);
  }
}

int Save::getInt(const std::string& key, int fallback) const {
  auto it = values_.find(key);
  if (it == values_.end()) return fallback;
  char* end = nullptr;
  const long v = std::strtol(it->second.c_str(), &end, 10);
  return end == it->second.c_str() ? fallback : int(v);
}

std::string Save::getString(const std::string& key) const {
  auto it = values_.find(key);
  return it == values_.end() ? "" : it->second;
}

void Save::set(const std::string& key, int value) { set(key, std::to_string(value)); }

void Save::set(const std::string& key, const std::string& value) {
  values_[key] = value;
  write();
}

void Save::write() const {
  std::ofstream out(path_, std::ios::trunc);
  for (auto& [k, v] : values_) out << k << '=' << v << '\n';
}
