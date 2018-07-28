#!/usr/bin/env python
#pick_cran_mirror.py - created Wed May 28 19:18:21 BST 2014

# Because R is so appallingly cack, and PyGTK is awesome, here's a Python picker to pick your CRAN mirror.

# Code based on https://developer.gnome.org/gnome-devel-demos/stable/treeview_simple_liststore.py.html.en
# and with help from this, of course:
# http://python-gtk-3-tutorial.readthedocs.org/en/latest/
# and:
# http://stackoverflow.com/questions/9945381/python-gtk-how-to-set-a-selected-row-on-gtk-treeview

from gi.repository import Gtk, Gdk
from gi.repository import Pango
import gi
gi.require_version("Gtk", "3.0")

import sys, traceback, os
import csv

columns = ["Mirror",
           "URL"]

# Yes I'm still calling this variable phonebook.
phonebook = []


class MyWindow(Gtk.ApplicationWindow):

    def __init__(self, app):
        Gtk.Window.__init__(self, title="Pick Your CRAN Mirror", application=app)
        self.set_default_size(250, 400)
        self.set_border_width(10)

	self.my_note = "Not all of these are reliable.  If in doubt stick with UK (Bristol)."

	#Flag allows clean cleanup
	self.failed = False

	self.default = -1
	self.load_phonebook()

	self.selection = ""

        # the data in the model (two strings for each row, one for each
        # column)
        liststore = Gtk.ListStore(str, str)
        # append the values in the model
        for i in phonebook:
            liststore.append(i)

        # a treeview to see the data stored in the model
        view = Gtk.TreeView(model=liststore)
        # for each column
        for i, colname in enumerate(columns):
            # cellrenderer to render the text
            cell = Gtk.CellRendererText()
            # the text in the first column should be in boldface
            if i == 0:
                cell.props.weight_set = True
                cell.props.weight = Pango.Weight.BOLD
            # the column is created
            # and it is appended to the treeview
            view.append_column(Gtk.TreeViewColumn(colname, cell, text=i))
	    view.get_columns()[i].set_sort_column_id(i)

        # the label we use to show the selection
        self.label = Gtk.Label()
        self.label.set_text("\n no selection")
	self.label.set_width_chars(30)

	# set default.  This looks tricky...  I should have spotted the desired index
	# during the load but can I just tell view to select it?  Ah, yes, seems so. :-)
	if self.default >= 0:
	    view.set_cursor(self.default)
	    view.scroll_to_cell(self.default, use_align=True, row_align=0.2)
	    self._on_changed( phonebook[self.default] )

        # when a row is selected, it emits a signal
        view.get_selection().connect("changed", self.on_changed)

	# also double-clicking should select.  This involves an event box
	#vieweb = Gtk.EventBox()
        view.connect("button-press-event", self.on_clicked)

	# a scrolly area to hold the tree view
	scrolly = Gtk.ScrolledWindow()
	scrolly.set_border_width(10)
	scrolly.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
	#scrolly.add_with_viewport(view) # note the subtle difference between this and...
	scrolly.add(view)
	scrolly.set_min_content_height(400)
	scrolly.set_hexpand(True)
	scrolly.set_vexpand(True)

	# a button to say when you are happy with the selection
	okbutton = Gtk.Button()
	okbutton.set_label("This one!")
	okbutton.connect("clicked", self.on_ok)

	lbl1 = Gtk.Label()
	lbl1.set_markup("\n<b>%s</b>\n" % self.get_title())

        # a grid to attach the widgets
        grid = Gtk.Grid()
        grid.attach(lbl1,                         0, 0, 2, 1)
        grid.attach(Gtk.Label(self.my_note),      0, 1, 2, 1)
        grid.attach(scrolly,                      0, 2, 2, 1)
        grid.attach(self.label,                   0, 3, 1, 1)
        grid.attach(okbutton,                     1, 3, 1, 1)

        # attach the grid to the window
        self.add(grid)

    def on_changed(self, selection):
        # get the model and the iterator that points at the data in the model
        (model, iter) = selection.get_selected()
	if iter != None:
	    self._on_changed(model[iter])

    def _on_changed(self, row):
        # set the label to a new value depending on the selection
        self.label.set_text("\n %s" % (row[0]))
	self.selection = row[1]
        return True

    def on_clicked(self, widget, event):
	if(event.type == Gdk.EventType._2BUTTON_PRESS):
	    self.on_ok(None)

    def on_ok(self, button):
	print(self.selection)
	self.destroy()

    def load_phonebook(self):
	# Loads the list of mirrors from the standard file location.  The variable is
	# called phonebook cos I nicked the phonebook code.
	try:
	    ml = csv.reader(open("/usr/share/R/doc/CRAN_mirrors.csv"))
	    for idx, row in enumerate(list(ml)[1:]):
		phonebook.append([row[0], row[3]])

		if(row[0] == "UK (Bristol)"):
		    self.default = idx
	except:
	    self.failed = True
    

class MyApplication(Gtk.Application):

    def __init__(self):
	Gtk.Application.__init__(self)

    def do_activate(self):
	try:
	    win = MyWindow(self)
	    if not win.failed:
		win.show_all()
	except:
	    # Needed to avoid hang on error
	    traceback.print_exc()
	    sys.exit(1)
	else:
	    # Warning - if win.failed is set the app exits with no error message at all.
	    # But that's what I want for my purposes.
	    if win.failed:
		sys.exit(1)

    def do_startup(self):
        Gtk.Application.do_startup(self)

app = MyApplication()
exit_status = app.run(sys.argv)
sys.exit(exit_status)
