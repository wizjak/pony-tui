cd /$HOME/.config
sleep 1
git clone https://github.com/wizjak/pony-tui
cd pony-tui
chmod +x listeps.sh
chmod +x pony-tui.sh
chmod +x pony-tui
sudo mv pony-tui /usr/local/bin
sudo chmod +x /usr/local/bin/pony-tui
echo done.
