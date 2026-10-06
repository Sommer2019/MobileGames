// Small key=value file for records and the dice history.
#pragma once

#include <map>
#include <string>

class Save {
 public:
  static Save& get();
  int getInt(const std::string& key, int fallback = 0) const;
  std::string getString(const std::string& key) const;
  void set(const std::string& key, int value);
  void set(const std::string& key, const std::string& value);

 private:
  Save();
  void write() const;
  std::string path_;
  std::map<std::string, std::string> values_;
};
