import Ember from 'ember';
import EmberObject from '@ember/object';
import { later as runLater, cancel as runCancel } from '@ember/runloop';
import {set as emberSet, get as emberGet} from '@ember/object';
import $ from 'jquery';
import editManager from './edit_manager';
import modal from './modal';
import capabilities from './capabilities';
import app_state from './app_state';
import i18n from './i18n';
import speecher from './speecher';
import buttonTracker from './raw_events';
import frame_listener from './frame_listener';

var scanner = EmberObject.extend({
  setup: function(controller) {
    this.controller = controller;
  },
  find_elem: function(search) {
    return $(search);
  },
  make_elem: function(tag, opts) {
    return $(tag, opts);
  },
  start: function(options) {
    scanner.current_element = null;
    scanner.ref = Math.random();
    if(scanner.find_elem("header #speak").length === 0) {
      console.debug("scanning currently only works in speak mode...");
      scanner.stop();
      return;
    }
    var rows = [];
    options = options || this.last_options;
    if(!options) { return; }

    this.last_options = options;
    options.scan_mode = options.scan_mode || "row";
    options.interval = options.interval || 1000;
    options.auto_start = options.auto_start || false;
    options.all_elements = [];

    var highlight_type = emberGet(modal.highlight_settings || {}, 'highlight_type');
    if((modal.is_open() && !modal.is_open('highlight')) || highlight_type == 'button_search') {
      return;
    } else if(options && options.scan_mode == 'axes') {
    } else {
      var row = {};
      if(!options.skip_header) {
        row = {
          children: [],
          dom: $("header"),
          header: true,
          label: i18n.t('header', "Header")
        };
        scanner.find_elem("header #speak").find("button:visible,#button_list,a.btn").each(function() {
          var id_labels = {
            'home_button': i18n.t('home', "Home"),
            'back_button': i18n.t('back', "Back"),
            'button_list': i18n.t('speak', "Speak"),
            'speak_options': i18n.t('options', "Speak Options"),
            'backspace_button': i18n.t('backspace', "Backspace"),
            'clear_button': i18n.t('clear', "Clear")
          };
          var $elem = scanner.find_elem(this);
          if($elem.attr('id') != 'speak_options') {
            var label = id_labels[$elem.attr('id')] || "";
            row.children.push({
              dom: $elem,
              label: label
            });
          }
        });

        var menu = {
          dom: scanner.find_elem("#identity a.btn"),
          label: i18n.t('menu', "Menu"),
          children: []
        };
        scanner.find_elem("#identity .dropdown-menu a").each(function() {
          var $option = scanner.find_elem(this);
          menu.children.push({
            dom: $option,
            label: $option.text()
          });
        });
        row.children.push(menu);

        // TODO: figure out sidebar, when teaser is visible and also when the
        // whole sidebar is visible, including toggling between the two
    //     if(scanner.find_elem("#sidebar_tease:visible").length) {
    //       row.children.push({
    //         dom: scanner.find_elem("#sidebar_tease")
    //       });
    //     }
        rows.push(row);
      }

      if(scanner.find_elem("#word_suggestions").length) {
        var row = {
          children: [],
          dom: scanner.find_elem("#word_suggestions"),
          header: true,
          label: i18n.t('suggestions', "Suggestions"),
          reload_children: function() {
            var res = [];
            scanner.find_elem("#word_suggestions").find(".suggestion").each(function() {
              var $elem = scanner.find_elem(this);
              res.push({
                dom: $elem,
                label: $elem.text()
              });
            });
            return res;
          }
        };
        row.children = row.reload_children();

        rows.push(row);
      }
      var content = scanner.scan_content();

      if(options.scan_mode == 'row' || options.scan_mode == 'button') {
        for(var idx = 0; idx < content.rows; idx++) {
          row = {
            children: [],
            dom: scanner.find_elem(),
            label: i18n.t('row_n', "Row %{n}", {n: (idx + 1)})
          };
          for(var jdx = 0; jdx < content.columns; jdx++) {
            var $button = content.order[idx][jdx];
            if($button.length) {
              row.dom = row.dom.add($button);
              row.children.push({
                dom: $button,
                label: $button.label,
                sound: $button.sound
              });
            }
          }
          if(row.children.length > 0) {
            if(row.children.length == 1) {
              row = row.children[0];
            }
            rows.push(row);
          }
        }
        if(rows.length == 1) {
          rows = rows[0].children;
        }
      } else if(options.scan_mode == 'column') {
        for(var idx = 0; idx < content.columns; idx++) {
          var column = {
            children: [],
            dom: scanner.find_elem(),
            label: i18n.t('column_n', "Column %{n}", {n: (idx + 1)})
          };
          for(var jdx = 0; jdx < content.rows; jdx++) {
            var $button = content.order[jdx][idx];
            if($button.length) {
              column.dom = column.dom.add($button);
              column.children.push({
                dom: $button,
                label: $button.label,
                sound: $button.sound
              });
            }
          }
          if(column.children.length > 0) {
            if(column.children.length == 1) {
              column = column.children[0];
            }
            rows.push(column);
          }
        }
        if(rows.length == 1) {
          rows = rows[0].children;
        }
      } else if(options.scan_mode == 'region') {
        var rows_per_chunk = options.rows_per_chunk;
        var columns_per_chunk = options.columns_per_chunk;
        var sub_scan = options.sub_scan_mode || 'horizontal';
        var vertical_chunks = Math.min(content.rows, options.vertical_chunks || Math.ceil(content.rows / (rows_per_chunk || 3)));
        var horizontal_chunks = Math.min(content.columns, options.horizontal_chunks || Math.ceil(content.columns / (columns_per_chunk || 3)));
        if(!rows_per_chunk || (rows_per_chunk < content.rows / vertical_chunks)) {
          rows_per_chunk = Math.max(Math.floor(content.rows / vertical_chunks), 1);
        }
        var leftover_rows = Math.max(content.rows - (rows_per_chunk * vertical_chunks), 0);
        if(!columns_per_chunk || (columns_per_chunk < content.columns / horizontal_chunks)) {
          columns_per_chunk = Math.max(Math.floor(content.columns / horizontal_chunks), 1);
        }
        var leftover_columns = Math.max(content.columns - (columns_per_chunk * horizontal_chunks), 0);
        var always_slice = true;
        if(sub_scan == 'vertical' || always_slice) {
          for(var idx = 0; idx < horizontal_chunks; idx++) {
            for(var jdx = 0; jdx < vertical_chunks; jdx++) {
              var chunk = {
                children: [],
                dom: scanner.find_elem(),
                label: i18n.t('region_n', "Region %{n}", {n: ((idx * vertical_chunks) + jdx + 1)})
              };
              var n_columns = columns_per_chunk;
              if(idx == horizontal_chunks - 1) { n_columns = n_columns + leftover_columns; }
              var n_rows = rows_per_chunk;
              if(jdx == vertical_chunks - 1) { n_rows = n_rows + leftover_rows; }
              for(var kdx = 0; kdx < n_columns; kdx++) {
                for(var ldx = 0; ldx < n_rows; ldx++) {
                  var r = content.order[(jdx * rows_per_chunk) + ldx];
                  if(r) {
                    var elem = r[(idx * columns_per_chunk) + kdx];
                    if(elem) {
                      var $button = elem;
                      if($button.length) {
                        chunk.dom = chunk.dom.add($button);
                        chunk.children.push({
                          dom: $button,
                          label: $button.label,
                          sound: $button.sound
                        });
                      }
                    }
                  }
                }
              }
              if(chunk.children.length > 0) {
                if(chunk.children.length == 1) {
                  chunk = chunk.children[0];
                }
                rows.push(chunk);
              }
            }
          }
        } else {
          for(var idx = 0; idx < vertical_chunks; idx++) {
            for(var jdx = 0; jdx < horizontal_chunks; jdx++) {
              var chunk = {
                children: [],
                dom: scanner.find_elem(),
                label: i18n.t('region_n', "Region %{n}", {n: ((idx * horizontal_chunks) + jdx + 1)})
              };
              for(var kdx = 0; kdx < rows_per_chunk; kdx++) {
                for(var ldx = 0; ldx < columns_per_chunk; ldx++) {
                  var r = content.order[(idx * rows_per_chunk) + kdx];
                  if(r) {
                    var elem = r[(jdx * columns_per_chunk) + ldx];
                    if(elem) {
                      var $button = elem;
                      if($button.length) {
                        var label = $button.label || "";
                        chunk.dom = chunk.dom.add($button);
                        chunk.children.push({
                          dom: $button,
                          label: $button.label,
                          sound: $button.sound
                        });
                      }
                    }
                  }
                }
              }
              if(chunk.children.length > 0) {
                if(chunk.children.length == 1) {
                  chunk = chunk.children[0];
                }
                rows.push(chunk);
              }
            }
          }
        }
        if(rows.length == 1) {
          rows = rows[0].children;
        }
      }
      if(options.scan_mode == 'button') {
        var new_rows = [];
        rows.forEach(function(row) {
          if(row.children && !row.header) {
            row.children.forEach(function(elem) {
              new_rows.push(elem);
            });
          } else {
            new_rows.push(row);
          }
        });
        rows = new_rows;
      }
    }
    this.scanning = true;
    this.element_index = null;
    this.element_index_advanced = !!options.auto_start;
    this.scan_elements(rows, options);
  },
  scan_content: function() {
    if(frame_listener.visible()) {
      var res = {};
      res.rows = 1;
      var items = frame_listener.active_targets() || [];
      res.columns = items.length;
      res.order = [];
      res.order[0] = [];
      items.forEach(function(item, idx) {
        var $elem = scanner.find_elem(item.dom);
        $elem.label = item.target.prompt || i18n.t('target_n', "target %{n}", {n: idx + 1});
        res.order[0].push($elem);
      });
      return res;
    } else {
      var grid = editManager.controller.get('model.grid');
      var res = {};
      res.rows = grid.rows;
      res.columns = grid.columns;
      res.order = [];
      for(var idx = 0; idx < grid.order.length; idx++) {
        res.order[idx] = [];
        for(var jdx = 0; jdx < grid.order[idx].length; jdx++) {
          var $button = scanner.find_elem(".button[data-id='" + grid.order[idx][jdx] + "']:not(.hidden_button)");
          var button = editManager.find_button(grid.order[idx][jdx]);
          $button.label = (button && (button.get('vocalization') || button.get('label'))) || "";
          $button.sound = (button && button.get('sound')) || null;
          res.order[idx][jdx] = $button;
        }
      }
      return res;
    }
  },
  reset: function(partial) {
    runCancel(scanner.interval);
    scanner.interval = null;
    modal.close_highlight();
    scanner.scan_axes('clear');
    if(partial !== true) {
      scanner.start();
      scanner.listen_for_input();
    }
  },
  stop: function()  {
    runCancel(scanner.interval);
    scanner.interval = null;
    this.scanning = false;
    this.keyboard_tried_to_show = false;
    this.last_options = null;
    modal.close_highlight();
    scanner.scan_axes('clear');
  },
  same_elements: function(a, b) {
    if(!a || !b || a.length != b.length) {
      return false;
    }
    for(var idx = 0; idx < a.length; idx++) {
      if(!a[idx] || !b[idx] || !a[idx].dom || !b[idx].dom || a[idx].dom[0] != b[idx].dom[0]) {
        return false;
      }
      if(a.children || b.children) {
        if(!a.children || !b.children || a.children.length != b.children.length) {
          return false;
        }
        if(!scanner.compare_elements(a.children, b.children)) {
          return false;
        }
      }
    }
    return true;
  },
  scan_elements: function(elements, options) {
    var retry = false;
    if(scanner.interval && scanner.same_elements(elements, this.elements)) {
      retry = true;
    }
    if(!retry) {
      this.elements = elements;
    }
    this.options = options;
    if(options && options.auto_start) {
      if(options && options.auto_scan) {
        this.element_index = 0;
      }
      this.next_element(retry);
    }
  },
  pick: function() {
    var elem = scanner.current_element;
    if(scanner.options && scanner.options.scan_mode != 'axes') {
      if((!modal.highlight_controller || !elem) && scanner.options && !scanner.options.auto_start) {
        scanner.next();
        return;
      }
      if(!modal.highlight_controller || !elem) { return; }
      var now = (new Date()).getTime();
      if(scanner.ignore_until && now < scanner.ignore_until) { return; }
    }

    var track = buttonTracker.track_selection({
      event_type: 'click',
      selection_type: 'scanner'
    });
    if(!track || !track.proceed) { return; }

    if(scanner.options && scanner.options.scan_mode == 'axes') {
      // progress to next scanning mode, or trigger select event at the coords
      scanner.scan_axes('next');
    } else {
      if(!elem.higher_level && elem.children && elem.children.length == 1) {
        elem = elem.children[0];
      }

      if(elem.dom && elem.dom.hasClass('integration_target')) {
        frame_listener.trigger_target_event(elem.dom[0], 'scanselect', 'select');
      }

      if(elem.dom && elem.dom.hasClass('btn') && elem.dom.closest("#identity").length > 0) {
        var e = $.Event( "click" );
        e.pass_through = true;
        e.switch_activated = true;
        scanner.find_elem(elem.dom).trigger(e);
        setTimeout(function() {
          scanner.find_elem("#home_button").focus().select();
        }, 100);
      }

      if(elem.higher_level) {
        scanner.elements = elem.higher_level;
        scanner.element_index = elem.higher_level_index;
        runCancel(scanner.interval);
        scanner.interval = runLater(function() {
          scanner.next_element();
        });
      } else if(elem.children) {
        scanner.load_children(elem, scanner.elements, scanner.element_index);
      } else if(elem.dom) {
        scanner.pick_elem(elem.dom);
      }
    }
    if(scanner.options && scanner.options.debounce) {
      scanner.ignore_until = now + scanner.options.debounce;
    }
  },
  pick_elem: function(dom) {
    var $closest = $(dom).closest('.button,.integration_target,.button_list');
    if($closest.length > 0) { dom = $closest; }
    scanner.element_index = 0;
    scanner.element_index_advanced = false;
    scanner.last_spoken_elem = null;
    var reset_now = true;
    if(dom.hasClass('button') && dom.attr('data-id')) {
      var id = dom.attr('data-id');
      var button = editManager.find_button(id);
      var app = app_state.controller;
      var board = app.get('board.model');
      // if button links to something else, don't resume scanning 
      // until board jumping has completed
      reset_now = false;
      app.activateButton(button, {board: board});
    } else if(dom.hasClass('integration_target')) {
      frame_listener.trigger_target(dom[0]);
    } else if(dom.hasClass('button_list')) {
      dom.select();
    } else {
      var e = $.Event( "click" );
      e.pass_through = true;
      scanner.find_elem(dom).trigger(e);
    }
    scanner.reset(true);
    var ref = scanner.ref;
    var cutoff = reset_now ? 0 : Math.max(scanner.options.interval, 500);
    scanner.reset_until = (new Date()).getTime() + cutoff;
    runLater(function() {
      if(ref == scanner.ref) {
        scanner.reset();
      }
    }, cutoff);
  },
  hide_input: function() {
    if(window.Keyboard && window.Keyboard.hide && app_state.get('speak_mode') && scanner.scanning) {
      if(this.find_elem("#hidden_input:focus").length > 0) {
        window.Keyboard.hide();
        window.Keyboard.hideFormAccessoryBar(true, function() { });
      }
    }
  },
  listen_for_input: function() {
    // Listens for bluetooth/external keyboard events. On iOS we only get those when
    // focused on a form element like a text box, which is actually lame and makes
    // things really complicated.

    var $elem = this.find_elem("#hidden_input");

    if($elem.length === 0) {
      var type = capabilities.system == 'iOS' ? 'text' : 'checkbox';

      // when in whole-screen-as-switch mode, don't bother listening for key events
      if(buttonTracker.left_screen_action || buttonTracker.right_screen_action) {
        type = 'checkbox';
      }

      $elem = this.make_elem("<input/>", {type: type, id: 'hidden_input', autocomplete: 'off', autocorrect: 'off', autocapitalize: 'off', spellcheck: 'off'});
      $elem.css({position: 'absolute', left: '-1000px'});
      document.body.appendChild($elem[0]);
    }
    if(this.find_elem("#hidden_input:focus").length === 0 && !this.keyboard_tried_to_show) {
      $elem.select().focus();
    }
//    scanner.hide_input();
  },
  axes_advance: function() {
    var do_continue = false;
    var rate = 100 / 3 / 60;
    if(scanner.options.sweep == 'quick') {
      rate = 100 / 2 / 60;
    } else if(scanner.options.sweep == 'speedy') {
      rate = 100 / 1 / 60;
    } else if(scanner.options.sweep == 'slow') {
      rate = 100 / 5 / 60;
    } else if(scanner.options.sweep == 'really_slow') {
      rate = 100 / 8 / 60;
    }

    if(scanner.axes.x == 'scanning-forward' || scanner.axes.x == 'scanning-backward') {
      var x = parseFloat(scanner.axes.vertical.style.left) || 0;
      if(scanner.axes.vertical.style.left == '-1000px') { x = 0; }
      if(scanner.axes.x.match(/forward/)) {
        x = x + rate;
      } else {
        x = x - rate;
      }
      if(x >= 100) {
        x = 100;
        scanner.axes.x = 'scanning-backward';
      } else if(x <= 0) {
        x = 0;
        scanner.axes.x = 'scanning-forward';
      }
      scanner.axes.vertical.style.left = x + 'vw';
      do_continue = true;
    }
    if(scanner.axes.y == 'scanning-forward' || scanner.axes.y == 'scanning-backward') {
      var min = 0;
      if(scanner.options.skip_header) {
        min = (document.getElementsByTagName('HEADER')[0].getBoundingClientRect().height / window.innerHeight) * 100;
      }
      var y = parseFloat(scanner.axes.horizontal.style.top) || min;
      if(scanner.axes.horizontal.style.top == '-1000px') { y = min; }
      if(scanner.axes.y.match(/forward/)) {
        y = y + rate;
      } else {
        y = y - rate;
      }
      if(y >= 100) {
        y = 100;
        scanner.axes.y = 'scanning-backward';
      } else if(y <= min) {
        y = min;
        scanner.axes.y = 'scanning-forward';
      }
      scanner.axes.horizontal.style.top = y + 'vh';
      do_continue = true;
    }
    if(do_continue) {
      scanner.axes.handling = true;
      window.requestAnimationFrame(scanner.axes_advance);
    } else {
      scanner.axes.handling = false;
    }
  },
  scan_axes: function(action) {
    if(!scanner.axes) {
      var vert = document.createElement('div');
      vert.id = 'scanner_axis_vertical';
      document.body.appendChild(vert);
      var horiz = document.createElement('div');
      horiz.id = 'scanner_axis_horizontal';
      document.body.appendChild(horiz);
      scanner.axes = {
        vertical: vert,
        horizontal: horiz
      };
    }
    if(action == 'start' && (scanner.axes.x || scanner.axes.y) && (!scanner.axes.x || !scanner.axes.y)) {
      // if already on the first type of scanning, ignore any restarts
    } else if(action == 'clear' || action == 'start') {
      // clear both axes
      scanner.axes.vertical.style.left = '-1000px';
      scanner.axes.horizontal.style.top = '-1000px';
      scanner.axes.x = null;
      scanner.axes.y = null;
    }
    if(!scanner.axes.x && !scanner.axes.y && (action == 'start' || action == 'next')) {
      // if neither is visible, go ahead and start one
      if(scanner.options && scanner.options.start_axis == 'y') {
        scanner.axes.y = 'scanning-forward';
        scanner.axes.x = null;
      } else {
        scanner.axes.x = 'scanning-forward';
        scanner.axes.y = null;
      }
      if(!scanner.axes.handling) { scanner.axes_advance(); }
    } else if((scanner.axes.x || scanner.axes.y) && (!scanner.axes.x || !scanner.axes.y) && action == 'next') {
      // if the other axis is visible, lock it in place and start the specified axis
      if(scanner.axes.x) {
        scanner.axes.x = 'fixed';
        scanner.axes.y = 'scanning-forward';
      } else {
        scanner.axes.y = 'fixed';
        scanner.axes.x = 'scanning-forward';
      }
      if(!scanner.axes.handling) { scanner.axes_advance(); }
    } else if(scanner.axes.x && scanner.axes.y && action == 'next') {
      // select what's under the axes
      var rect = scanner.axes.vertical.getBoundingClientRect();
      var x = rect.left + (rect.width / 2);
      rect = scanner.axes.horizontal.getBoundingClientRect();
      var y = rect.top + (rect.height / 2);
      scanner.options.auto_start = true;
      (scanner.last_options || {}).auto_start = true;
      scanner.scan_axes('clear');
      // simulate selection event at the current location
      var target = document.elementFromPoint(x, y);
      scanner.pick_elem($(target));
      runLater(scanner.reset);
    }
  },
  load_children: function(elem, elements, index) {
    var parent = $.extend({higher_level: elements, higher_level_index: index}, elem);
    if(elem.reload_children) {
      elem.children = elem.reload_children();
    }
    scanner.elements = elem.children.concat([parent]);
    scanner.element_index = 0;
    scanner.element_index_advanced = !!parent.higher_level;
    runCancel(scanner.interval);
    scanner.interval = runLater(function() {
      scanner.next_element();
    });
  },
  next: function(reverse) {
    var now = (new Date()).getTime();
    if(scanner.ignore_until && now < scanner.ignore_until) { console.log("ignoring because too soon"); return; }
    if(scanner.reset_until && now < scanner.reset_until) { 
      scanner.reset_until = null;
      scanner.reset();
      if(scanner.options && !scanner.options.auto_start) {
        runLater(function() { scanner.next(reverse); });
      }
      return; 
    }
    if(!scanner.element_index_advanced) { scanner.element_index = -1; }
    runCancel(scanner.interval);
    scanner.interval = null;
    scanner.element_index_advanced = true;
    scanner.last_spoken_elem = null;
    if(scanner.options && scanner.options.scan_mode == 'axes') {
      // ignore
    } else {
      scanner.element_index = scanner.element_index + (reverse ? -1 : 1);
      if(scanner.element_index >= scanner.elements.length) {
        scanner.element_index = 0;
      } else if(scanner.element_index < 0) {
        scanner.element_index = scanner.elements.length - 1;
      }
      scanner.next_element();
      if(scanner.options && scanner.options.debounce) {
        scanner.ignore_until = now + scanner.options.debounce;
      }
    }
  },
  prev: function() {
    scanner.next(true);
  },
  next_element: function(retry) {
    var elem = this.elements[this.element_index];
    if(scanner.options && scanner.options.scan_mode == 'axes') {
      scanner.scan_axes('start');
      return;
    }
    if(!elem) {
      elem = elem || this.elements[0];
      this.element_index = 0;
    }
    if(!document.body.contains(elem.dom[0])) {
      var last = this.elements[this.elements.length - 1];
      if(last && last.higher_level && last.reload_children) {
        scanner.load_children(last.higher_level[last.higher_level_index], last.higher_level, last.higher_level_index);
        return;
      }
    }
    scanner.current_element = elem;
    var options = scanner.options || {};
    options.prevent_close = true;
    options.overlay = false;
    options.select_anywhere = true;
    // Only prevent auto-start at the first iteration, after that
    // go ahead and resume whenever it stops
    // options.auto_start = true;
    if(scanner.options && scanner.options.focus_overlay) {
      options.overlay = true;
      options.clear_overlay = false;
    }

    // Don't repeat
    if(!retry) {
      if(this.options && this.options.audio && this.last_spoken_elem != elem.dom[0]) {
        this.last_spoken_elem = elem.dom[0];
        var alt_voice = !!(speecher.alternate_voice && speecher.alternate_voice.enabled && speecher.alternate_voice.for_scanning !== false);
        if(elem && elem.sound) {
          speecher.speak_audio(elem.sound, 'text', false, {alternate_voice: alt_voice, interrupt: false});
        } else if(elem && elem.label) {
          var clean_label = (elem.label || "").replace(/^[\+\:]/, '');
          speecher.speak_text(clean_label, false, {alternate_voice: alt_voice, interrupt: false});
        }
      }
    }
    scanner.listen_for_input();
    if(capabilities.mobile && capabilities.installed_app && app_state.get('speak_mode') && scanner.find_elem("#hidden_input:focus").length === 0 && !scanner.keyboard_tried_to_show) {
      modal.warning(i18n.t('tap_first', "Your switch may not be completely enabled. Tap somewhere on the screen to finish enabling it."), true);
    }
    if(elem.dom.hasClass('integration_target')) {
      frame_listener.trigger_target_event(elem.dom[0], 'scanover', 'over');
    }
    modal.highlight(elem.dom, options).then(function() {
      if(!buttonTracker.any_select) {
        scanner.pick();
      }
    }, function() { });
    // Don't repeat
    if(!retry || !scanner.interval) {
      if(options.auto_scan !== false) {
        scanner.interval = runLater(function() {
          if(scanner.current_element == elem) {
            if(scanner.options && scanner.options.scanning_auto_select) {
              scanner.pick();
            } else {
              scanner.next();
            }
          }
        }, Math.max(options.interval || 1000, 500));
      }
    }
  }
}).create();
window.addEventListener('keyboardWillShow', function() {
  if(window.Keyboard && window.Keyboard.hide && app_state.get('speak_mode') && scanner.scanning) {
    scanner.keyboard_tried_to_show = true;
  }
  scanner.hide_input();
});
window.scanner = scanner;

export default scanner;
