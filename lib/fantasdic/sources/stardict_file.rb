# Fantasdic
# Copyright (C) 2008-2009 Mathieu Blondel
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

module Fantasdic
module Source

class StardictInfo < Hash

    def initialize(file_path)
        File.open(file_path) { |f| parse(f) }
    end

    def xdxf?
        if has_key? "sametypesequence" and self["sametypesequence"] == "x"
            true
        else
            false
        end
    end

    def pango_markup?
        if has_key? "sametypesequence" and self["sametypesequence"] == "g"
            true
        else
            false
        end
    end

    private

    def parse(f)
        f.each_line do |line|
            key, value = line.strip.split("=").map { |s| s.strip }
            next if value.nil?
            if ["wordcount", "idxfilesize"].include?(key)
                self[key] = value.to_i
            else
                self[key] = value
            end
        end
    end

end

class StardictIndex < DictionaryIndex

    OFFSET_INT_SIZE = 4
    LEN_INT_SIZE = 4

    def initialize(*args)
        super(*args)
    end

    def open(*args)
        super(*args)
    end

    def self.get_fields(str)
        i = str.index("\0")
        word = str.slice(0...i)
        word_offset = str.slice((i+1)..(i+OFFSET_INT_SIZE))
        word_len = \
            str.slice((i+OFFSET_INT_SIZE+1)..(i+OFFSET_INT_SIZE+LEN_INT_SIZE))

        word_offset = word_offset.nbo32_to_integer
        word_len = word_len.nbo32_to_integer

        [word, word_offset, word_len]
    end

    def get_fields(offset, len=0)
        self.seek(offset)
        if len > 0
            buf = self.read(len)
        else
            # we don't know the size so we read the maximum entry size
            buf = self.read(256 + 1 + OFFSET_INT_SIZE + LEN_INT_SIZE)
        end
        self.class.get_fields(buf)
    end

    def match_binary_search(word, &comp)
        offsets = self.get_index_offsets

        found_indices = offsets.binary_search_all(word) do |offset, word|
            curr_word, curr_offset, curr_len = self.get_fields(offset)
            comp.call(curr_word.downcase, word.downcase)
        end

        found_offsets = found_indices.map { |i| offsets[i] }

        found_offsets.map { |offset| self.get_fields(offset) }
    end

    # Returns the offsets of the beginning of each entry in the index
    def get_index_offsets
        self.rewind
        buf = self.read # FIXME: don't load the whole index into memory
        len = buf.length
        offset = 0

        offsets = []

        while offset < len
            offsets << offset
            i = buf.index("\0", offset)
            break unless i
            offset = i + OFFSET_INT_SIZE + LEN_INT_SIZE + 1
        end

        offsets
    end

    def get_word_list
        self.rewind
        buf = self.read # FIXME: don't load the whole index into memory
        len = buf.length
        offset = 0

        words = []

        while offset < len
            i = buf.index("\0", offset)
            break unless i
            end_offset = i + OFFSET_INT_SIZE + LEN_INT_SIZE
            words << StardictIndex.get_fields(buf.slice(offset..end_offset))
            offset = end_offset + 1
        end

        words
    end

end

class StardictFile < Base

    authors ["Mathieu Blondel"]
    title  _("Stardict file")
    description _("Look up words in Stardict files.")
    license Fantasdic::GPL
    copyright "Copyright (C) 2008-2009 Mathieu Blondel"
    no_databases true

    STRATEGIES_DESC = {
        "define" => "Results match with the word exactly.",
        "prefix" => "Results match with the beginning of the word.",
        "word" => "Results have one word that matches with the word.",
        "substring" => "Results have a portion that contains the word.",
        "suffix" => "Results match with the end of the word.",
        "stem" => "Results share the same root as the word.",
        "lev" => "Results are close to the word according to the " + \
                 "levenshtein distance.",
        "soundex" => "Results have similar pronunciation according " + \
                     "to the soundex algorithm.",
        "metaphone" => "Results have similar pronunciation according " + \
                       "to the metaphone algorithm.",
        "metaphone2" => "Results have similar pronunciation according " + \
                       "to the double metaphone algorithm.",
        "regexp" => "Results match the regular expression."
    }

    class ConfigWidget < FileSource::ConfigWidget

        def initialize(*args)
            super(*args)

            @choose_file_message = _("Select a dictd file")
            @file_extensions = [["*.ifo", _("Ifo files")]]
            @encodings = []

            initialize_ui
            initialize_data
            initialize_signals
        end

    end

    def check_validity
        stardict_file_open do |index_file, dict_file, file_info|
            n_offsets = index_file.get_index_offsets.length
            n_words = file_info["wordcount"]

            if n_offsets != n_words
                raise Source::SourceError,
                    _("Wrong .ifo or .idx file!")
            end
        end
    end

    def available_strategies
        STRATEGIES_DESC
    end

    def define(db, word)
        db = File.basename(@config[:filename]).slice(0...-6)
        db_capitalize = db.capitalize

        stardict_file_open do |index_file, dict_file, file_info|
            index_file.match_exact(word).map do |match, offset, len|
                defi = Definition.new
                defi.word = match
                defi.body = get_definition(dict_file, offset, len).strip
                xdxf_to_pangomarkup!(defi.body) if file_info.xdxf?
                defi.database = db
                defi.description = db_capitalize
                defi
            end
        end
    end

    def match(db, strat, word)
        matches = stardict_file_open do |index_file, dict_file, file_info|
            meth = "match_#{strat}"
            if index_file.respond_to? meth
                index_file.send(meth, word)
            else
                []
            end.map do |match, offset, len|
                match
            end
        end

        hsh = {}
        db = File.basename(@config[:filename])
        hsh[db] = matches unless matches.empty?
        hsh
    end

    private

    def get_definition(file, offset, len)
        file.pos = offset
        file.read(len)
    end

    def stardict_file_open
        idx_file = @config[:filename].gsub(/.ifo/, ".idx")
        dict_file = @config[:filename].gsub(/.ifo/, ".dict")
        dict_gz_file = dict_file + ".dz"

        [@config[:filename], idx_file].each do |mandatory_file|
            if !File.readable? mandatory_file
                raise Source::SourceError,
                        _("Cannot open file %s.") % mandatory_file
            end
        end

        if !File.readable? dict_file and !File.readable? dict_gz_file
            raise Source::SourceError,
            _("Couldn't find .dict or .dict.dz dictionary file.")
        elsif File.readable? dict_file
            dict_file = File.new(dict_file)
        else
            begin
                dict_file = Dictzip.new(dict_gz_file)
            rescue DictzipError => e
                raise Source::SourceError, e.to_s
            end
        end

        index_file = StardictIndex.new(idx_file)
        file_info = StardictInfo.new(@config[:filename])

        if block_given?
            ret = yield(index_file, dict_file, file_info)

            index_file.close
            dict_file.close

            ret
        else
            [index_file, dict_file, file_info]
        end
    end

    XDXF_TO_PANGOMARKUP = [["<k>", "<b>"],
                           ["</k>", "</b>"],
                           ["<c c=", "<span color="],
                           ["</c>", "</span>"],
                           ["<kref>", "{"],
                           ["</kref>", "}"],
                           ["<abr>", ""],
                           ["</abr>", ""],
                           ["<pos>", "<small><i>"],
                           ["</pos>", "</i></small>"],
                           ["<blockquote>", "<i>"],
                           ["</blockquote>", "</i>"],
                           ["<opt>", "<span color=\"grey\">"],
                           ["</opt>", "</span>"],
                           ["<nu>", ""],
                           ["</nu>", ""],
                           ["<def>", ""],
                           ["</def>", ""],
                           ["<tense>", "<i>"],
                           ["</tense>", "</i><"],
                           ["<tr>", "<i>"],
                           ["</tr>", "</i>"],
                           ["<dtrn>", "<i>"],
                           ["</dtrn>", "</i>"],
                           ["<ex>", "<span color=\"grey\">"],
                           ["</ex>", "</span>"],
                           ["<co>", "<span color=\"blue\">"],
                           ["</co>", "</span>"]]

    def xdxf_to_pangomarkup!(txt)
        XDXF_TO_PANGOMARKUP.each do |from, to|
            txt.gsub!(from, to)
        end
    end

end

end
end

Fantasdic::Source::Base.register_source(Fantasdic::Source::StardictFile)