#!/usr/bin/env python3
"""Compile the original news selection/cleanup functions from OpenTTD 16.0-RC1."""
import argparse
import hashlib
import re
from pathlib import Path
import random
import subprocess
import tempfile

from road_loading_upstream import extract

ROOT = Path(__file__).resolve().parents[1]
PIN = {
    "news_gui.cpp": "e01564b7e42f0294f82d3e5f5d7331a58bd6c1a7a425f121c765ebb61c178b77",
    "news_display_settings.ini": "6cf6d4614c765c46559938a8fa11c58c322ccbbdaf860521c1083fea6fbb5087",
    "gui_settings.ini": "e2bf3ac20d3838fe0e08b9f6b0425c260449df2a8f72d32f1e6a7cc4ec5993db",
}
CPP = r"""
#include <array>
#include <cstdlib>
#include <iostream>
#include <list>
#include <iterator>
enum class NewsDisplay {Off,Summary,Full};
enum class WindowClass {Statusbar,News,MessageHistory};
enum {SBI_SHOW_REMINDER};
constexpr unsigned MIN_NEWS_AMOUNT=30;
#define NOT_REACHED() std::abort()
struct TimerGameEconomy {static inline int date=0;};
struct NewsTypeData {
  int age,display;
  NewsDisplay GetDisplay() const {return NewsDisplay(display);}
};
std::array<NewsTypeData,16> _news_type_data;
struct Settings {struct {int news_message_timeout;} gui;} _settings_client;
struct NewsItem {int seq,type,economy_date;};
std::list<NewsItem> _news;
using NewsIterator=std::list<NewsItem>::const_iterator;
NewsIterator _current_news,_forced_news,_statusbar_news;
bool paper_shown;
using Window=int;
using NewsType=int;
Window *FindWindowById(WindowClass w,int) {
  static int win;
  return w==WindowClass::Statusbar || paper_shown ? &win : nullptr;
}
void CloseWindowById(WindowClass w,int) {if(w==WindowClass::News) paper_shown=false;}
void InvalidateWindowData(WindowClass w,int,int why=-1) {
  if(w==WindowClass::Statusbar && why==SBI_SHOW_REMINDER) std::cout<<_statusbar_news->seq<<":0,";
}
void ShowTicker(NewsIterator i) {std::cout<<i->seq<<":1,";}
void ShowNewspaper(const NewsItem *ni) {std::cout<<ni->seq<<":2,";paper_shown=true;}
void ShowNewsMessage(NewsIterator i) { _forced_news=i;std::cout<<i->seq<<','; }
auto DeleteNewsItem(NewsIterator i) {return _news.erase(i);}
"""
DRIVER = r"""
int main() {
  for (int i=0;i<16;i++) std::cin>>_news_type_data[i].age>>_news_type_data[i].display;
  int count,now,timeout;
  while(std::cin>>count>>now>>timeout) {
    _news.clear();
    _settings_client.gui.news_message_timeout=timeout;
    TimerGameEconomy::date=now;
    for(int i=1;i<=count;i++) {
      int type,stamp;std::cin>>type>>stamp;
      _news.emplace_front(NewsItem{i,type,stamp});
    }
    _current_news=_forced_news=_statusbar_news=std::end(_news);
    paper_shown=false;
    for(int i=0;i<count;i++) MoveToNextTickerItem();
    std::cout<<'|';
    for(int i=0;i<count;i++) MoveToNextNewsItem();
    std::cout<<'|';
    for(int i=0;i<3;i++) ShowLastNewsMessage();
    std::cout<<'|';
    RemoveOldNewsItems();
    for(const auto &i:_news) std::cout<<i.seq<<',';
    std::cout<<'\n';
  }
}
"""
LUA = r"""
local N=dofile('mods/luanttd_core/openttd/news.lua')
local function values(line)
  local out={}
  for n in line:gmatch('%-?%d+') do out[#out+1]=tonumber(n) end
  return out
end
local source=values(io.read())
for i,c in ipairs(N.categories) do assert(c[2]==source[i*2-1] and c[3]==source[i*2],c[1]) end
for line in io.lines() do
  local input=values(line)
  local count,now,timeout=input[1],input[2],input[3]
  local book=N.new()
  for i=1,count do N.push(book,{kind=N.categories[input[i*2+2]+1][1],economy=input[i*2+3]}) end
  local rows={}
  for i=count,1,-1 do rows[#rows+1]=book.items[i] end
  local r={}
  local function lane(name)
    local cursor,last=0,nil
    for _=1,count do
      local row,at,mode=N.next_auto(rows,cursor,name,now)
      cursor=at
      last=row
      if row then r[#r+1]=row.seq..':'..mode..',' end
    end
    return cursor,last
  end
  lane('ticker');r[#r+1]='|'
  local current,last=lane('paper');r[#r+1]='|'
  local forced
  for _=1,3 do
    local row=N.last(book.items,forced,current,last~=nil)
    if row then forced=row.seq;r[#r+1]=forced..',' end
  end
  r[#r+1]='|'
  N.cleanup(book,now,12,timeout)
  for _,row in ipairs(book.items) do r[#r+1]=row.seq..',' end
  print(table.concat(r))
end
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--lua", default="lua5.1")
    args = parser.parse_args()

    def read(name):
        for directory in ("", "src", "src/table/settings"):
            file = args.source / directory / name
            if file.exists():
                data = file.read_bytes()
                assert hashlib.sha256(data).hexdigest() == PIN[name], file
                return data.decode()
        raise FileNotFoundError(name)

    cpp = read("news_gui.cpp")
    settings = read("news_display_settings.ini")
    default = dict(re.findall(r"var += news_display.([a-z_]+)\n[^[]*?def += (\d+)", settings))
    spec = re.findall(r'NewsTypeData\("news_display\.([a-z_]+)",\s+(\d+),', cpp)
    assert len(spec) == len(default) == 16
    assert re.search(r"gui.news_message_timeout\n[^[]*?def += 2\n", read("gui_settings.ini"))
    assert re.search(r"NewsWindow::duration = 16650;", cpp)
    assert "MIN_NEWS_AMOUNT = 30" in cpp and "MAX_NEWS_AMOUNT = 1U << 10" in cpp
    functions = ("static void MoveToNextTickerItem(", "static void MoveToNextNewsItem(",
                 "template <size_t Tmin = 0, class Tpredicate>\nvoid DeleteNews(",
                 "static void RemoveOldNewsItems(", "void ShowLastNewsMessage(")
    original = "\n".join(extract(cpp, signature) for signature in functions)
    rows = [" ".join(f"{age} {default[kind]}" for kind, age in spec)]
    rng = random.Random(160)
    for _ in range(240):
        n, now, timeout = rng.randrange(1, 100), rng.randrange(1, 600), rng.randrange(1, 7)
        a = [n, now, timeout]
        for day in sorted(rng.randrange(0, now) for _ in range(n)):
            a.extend((rng.randrange(16), day))
        rows.append(" ".join(map(str, a)))
    data = ("\n".join(rows) + "\n").encode()
    with tempfile.TemporaryDirectory() as path:
        path = Path(path)
        (path / "stock.cpp").write_text(CPP + original + DRIVER)
        (path / "port.lua").write_text(LUA)
        subprocess.run(["g++","-std=c++20","-O2",path/"stock.cpp","-o",path/"stock"], check=True)
        stock = subprocess.check_output([path/"stock"], input=data).splitlines()
        port = subprocess.check_output([args.lua,path/"port.lua"], input=data, cwd=ROOT).splitlines()
    assert len(stock) == len(port) == len(rows)-1
    for line,want,got in zip(rows[1:],stock,port,strict=True):
        assert want==got,(line,want,got)
    print("PASS 240 compiled 16.0-RC1 news cases: exact categories, auto lane/order/age, forced replay, history prune")

if __name__=="__main__":
    main()
