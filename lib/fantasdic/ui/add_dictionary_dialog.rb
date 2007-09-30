# Fantasdic
# Copyright (C) 2006 Mathieu Blondel
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
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

module Fantasdic
module UI

    class DatabaseInfoDialog < GladeBase
        include GetText
        GetText.bindtextdomain(Fantasdic::TEXTDOMAIN, nil, nil, "UTF-8")

        def initialize(db)
            super("server_infos_dialog.glade")
            @dialog.title = _("About database %s") % db
            initialize_signals
        end

        def initialize_signals
            @dialog.signal_connect("delete-event") { @dialog.hide }
            @close_button.signal_connect("clicked") { @dialog.hide }
        end

        def text
            @textview.buffer.text
        end

        def text=(txt)
            @textview.buffer.text = txt if txt and !txt.empty?
        end
    end

    class AddDictionaryDialog < GladeBase
        include GetText
        GetText.bindtextdomain(Fantasdic::TEXTDOMAIN, nil, nil, "UTF-8")

        MAX_TV = 30
        MAX_CB = 18

        NAME = 0
        DESC = 1

        PAGE_GENERAL_INFORMATIONS = 0
        PAGE_DATABASES = 1

        SOURCE_TITLE = 0
        SOURCE_SHORT_NAME = 1

        def initialize(parent, dicname=nil, hash=nil, &callback_proc)
            super("add_dictionary_dialog.glade")
            @dialog.transient_for = parent
            @prefs = Preferences.instance
            @dicname = dicname
            @hash = hash
            @callback_proc = callback_proc
            initialize_ui
            initialize_signals
            initialize_data
        end

        private

        def sel_dbs_have?(name)
            ret = false
            @sel_db_treeview.model.each do |model, path, iter|
                ret = true if iter[NAME] == name
            end
            ret
        end

        def status_bar_msg=(message)
            @statusbar.push(0, message)
        end

        def close!
            @dialog.hide
        end

        def sensitize_move_up
            @move_up_button.sensitive = @sel_db_treeview.has_row_selected?     
        end

        def sensitize_move_down
            @move_down_button.sensitive = \
                @avail_db_treeview.has_row_selected?
        end

        def initialize_data
            # Main fields
            @name_entry.text = @dicname if @dicname

            if @hash
                # Font buttons
                if @hash[:print_font_name]
                    @print_fontbutton.font_name = @hash[:print_font_name]
                else
                    @print_fontbutton.font_name = Print::DEFAULT_FONT.to_s
                end

                if @hash[:results_font_name]                
                    @results_fontbutton.font_name = @hash[:results_font_name]
                else
                    @results_fontbutton.font_name = \
                        LinkBuffer::DEFAULT_FONT.to_s
                end

                # Selected dbs
                if !@hash[:all_dbs]
                    @sel_db_radiobutton.active = true
                end
            end
        end

        def initialize_signals
            initialize_dialog_buttons_signals
            initialize_dictionaries_signals
            initialize_font_signals
        end

        def initialize_font_signals
            @set_default_fonts_button.signal_connect("clicked") do
                @results_fontbutton.font_name = LinkBuffer::DEFAULT_FONT.to_s
                @print_fontbutton.font_name = Print::DEFAULT_FONT.to_s
            end
        end

        def initialize_dictionaries_signals
            @move_up_button.signal_connect("clicked") do
                iters = []
                @sel_db_treeview.selection.selected_each do |model, path, iter|
                    iters << iter
                end
                iters.each { |iter| @sel_db_treeview.model.remove(iter) }
                @avail_db_treeview.selection.unselect_all

                @all_db_radiobutton.activate if @sel_db_treeview.model.empty?
            end

            @move_down_button.signal_connect("clicked") do
                @avail_db_treeview.selection.selected_each do |model,
                                                               path,
                                                               iter|
                    unless sel_dbs_have? iter[NAME]
                        row = @sel_db_treeview.model.append
        
                        row[NAME] = iter[NAME]
                        row[DESC] = iter[DESC]
                    end
                end
                @avail_db_treeview.selection.unselect_all

                @sel_db_radiobutton.activate
            end

            @sel_db_treeview.selection.signal_connect("changed") do
                sensitize_move_up
            end

            @avail_db_treeview.selection.signal_connect("changed") do
                sensitize_move_down
            end

            [@avail_db_treeview, @sel_db_treeview].each do |tv|
                # Double click on row: show db infos
                tv.signal_connect("row-activated") do |view, path, column|
                    iter = tv.model.get_iter(path)
                    dbname = iter[NAME]
                    dg = DatabaseInfoDialog.new(dbname)
                    dg.text = @source.database_info(dbname)
                end

                # Renderer which slice too long names
                renderer = Gtk::CellRendererText.new
                col = Gtk::TreeViewColumn.new("Database", renderer)
                
                col.set_cell_data_func(renderer) do |col, renderer, model, iter|
                    str = "%s (%s)" % [iter[NAME], iter[DESC]]
                    str = str.utf8_slice(0..40) + "..." \
                            if str.utf8_length > 50
                    renderer.text = str
                end
                tv.append_column(col)
            end
        end

        def initialize_dialog_buttons_signals
            @show_help_button.signal_connect("clicked") do
                Browser::open_help("fantasdic-dictionaries")
            end

            @cancel_button.signal_connect("clicked") do
                close!
            end

            @dialog.signal_connect("delete-event") do
                close!
            end

            @source_combobox.signal_connect("changed") do
                set_source(selected_source)
            end

            @add_button.signal_connect("clicked") do
                add_dictionary
            end
        end

        def add_dictionary
            checks = [
                @name_entry.text.empty?,

                (@sel_db_radiobutton.active? and
                @sel_db_treeview.model.empty?)
            ]

            checks.each do |expr|
                if expr == true
                    ErrorDialog.new(@dialog, _("Fields missing"))
                    return false
                end
            end

            if @prefs.dictionary_exists? @name_entry.text and \
                !@update_dialog

                ErrorDialog.new(@dialog,
                                _("Dictionary %s exists already!") % \
                                    @name_entry.text)
                return false
            end

            hash = {}

            # Merges configuration information from source
            begin
                hash.merge!(@source.to_hash)
            rescue Source::SourceError => e
                ErrorDialog.new(@dialog, e)
                return false
            end

            hash[:all_dbs] = @all_db_radiobutton.active?

            hash[:sel_dbs] = []
            @sel_db_treeview.model.each do |model, path, iter|
                hash[:sel_dbs] << iter[NAME]
            end

            hash[:avail_strats] = @source.available_strategies.map { |s| s[0] }
            hash[:sel_strat] = "define" # default strat

            hash[:results_font_name] = @results_fontbutton.font_name
            hash[:print_font_name] = @print_fontbutton.font_name

            hash[:source] = selected_source

            @callback_proc.call(@name_entry.text, hash)

            close!
        end

        def initialize_ui
            @print_vbox.visible = Fantasdic::UI::HAVE_PRINT

            @avail_db_treeview.model = Gtk::ListStore.new(String, String)
            @avail_db_treeview.selection.mode = Gtk::SELECTION_MULTIPLE

            @sel_db_treeview.model = Gtk::ListStore.new(String, String)
            @sel_db_treeview.selection.mode = Gtk::SELECTION_MULTIPLE

            # Update source list
            @source_combobox.model = Gtk::ListStore.new(String, String)
            Source::Base.registered_sources.each do |source|
                iter = @source_combobox.model.append
                iter[SOURCE_TITLE] = source.title
                iter[SOURCE_SHORT_NAME] = source.short_name
            end

            if @hash and @hash[:source]
                # it means we are updating an existing dictionary
                # as opposed to adding a new one
                @update_dialog = true
                self.selected_source = @hash[:source]
            elsif 
                self.selected_source = Source::Base::DEFAULT_SOURCE
            end

            @dialog.show_all

            set_source(selected_source)
        end

        def update_db_list(dont_update_sel_dbs=false)
            @general_infos_vbox.sensitive = false
            @databases_vbox.sensitive = false

            @avail_db_treeview.model.clear
            @sel_db_treeview.model.clear

            self.status_bar_msg = _("Fetching databases information...")

            begin
                dbs = @source.available_databases

                sel_db_desc = {}

                # Add available databases
                dbs.keys.sort.each do |name|
                    row = @avail_db_treeview.model.append

                    row[NAME] = name
                    row[DESC] = dbs[name]

                    if !@hash.nil? and !@hash[:sel_dbs].nil? and \
                        @hash[:sel_dbs].include? name
                        sel_db_desc[name] = row[DESC]
                    end
                end

                # Add selected databases
                if !@hash.nil? and !@hash[:sel_dbs].nil? and \
                   !dont_update_sel_dbs and @hash[:source] == selected_source
                    @hash[:sel_dbs].each do |name|
                        unless sel_db_desc[name].nil?
                            row = @sel_db_treeview.model.append
        
                            row[NAME] = name
                            row[DESC] = sel_db_desc[name]
                        end
                    end
                    @sel_db_radiobutton.activate
                else
                    @all_db_radiobutton.activate
                end
                self.status_bar_msg = ""
                @add_button.sensitive = true
            rescue Source::SourceError => e
                @add_button.sensitive = false
                self.status_bar_msg = e
            ensure                
                @general_infos_vbox.sensitive = true
                @databases_vbox.sensitive = true
            end
        end

        def set_source(src_str)
            # Remove previous config widget if any
            if @config_widget
                @general_infos_vbox.remove(@config_widget)
            end
           
            @source = Source::Base.get_source(src_str).new(@dialog, @hash) do
                # This block is called when databases list needs be updated
                Thread.new { update_db_list }
            end

            # Sets the config widget
            @config_widget = @source.config_widget

            if @config_widget
                # pack_start(widget, expand, fill, padding)
                @general_infos_vbox.pack_start(@config_widget, false, false, 0)
                @general_infos_vbox.show_all
            end

            Thread.new { update_db_list }
        end

        def selected_source
            n = @source_combobox.active
            @source_combobox.model.get_iter(n.to_s)[SOURCE_SHORT_NAME] if n >= 0
        end

        def selected_source=(source)
            n = 0
            @source_combobox.model.each do |model, path, iter|
                if iter[SOURCE_SHORT_NAME] == source
                    @source_combobox.active = n
                    break
                end
                n += 1
            end
        end
      
    end
        
end
end
