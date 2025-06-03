#include <boost/container_hash/hash.hpp>
#include <iostream>
#include <string>

int main() {
    std::string s = "hello";
    std::size_t h = boost::hash<std::string>()(s);
    std::cout << "Hash: " << h << std::endl;
    return 0;
}
