import Ember from 'ember';
import scanner from './scanner';

var modal = Ember.Object.extend({
  setup: function(route) {
    if(this.last_promise) { this.last_promise.reject('closing due to setup'); }
    this.route = route;
    this.settings_for = {};
    this.controller_for = {};
  },
  reset: function() {
    this.route = null;
  },
  open: function(template, options) {
    if(template != 'highlight' && scanner.scanning) {
      this.resume_scanning = true;
      scanner.stop();
    }
    // TODO: one option should be to have a gray background (dull out the
    // prior context as unimportant), which would be used in the new-board modal
    if((this.last_promise || this.last_template) && template != 'highlight') {
      this.close();
    }
    if(!this.route) { throw "must call setup before trying to open a modal"; }

    this.settings_for[template] = options;
    this.last_template = template;
    this.route.render(template, { into: 'application', outlet: 'modal'});
    var _this = this;
    return new Ember.RSVP.Promise(function(resolve, reject) {
      _this.last_promise = {
        resolve: resolve,
        reject: reject
      };
    });
  },
  is_open: function(template) {
    if(template) {
      return this.last_template == template;
    } else {
      return !!this.last_template;
    }
  },
  is_closeable: function() {
    return Ember.$(".modal").attr('data-uncloseable') != 'true';
  },
  queue: function(template) {
    if(this.is_open()) {
      this.queued_template = template;
    } else {
      this.open(template);
    }
  },
  highlight: function($elems, options) {
    var minX, minY, maxX, maxY;
    $elems.each(function() {
      var $e = Ember.$(this);
      var offset = $e.offset();
      var thisMinX = offset.left;
      var thisMinY = offset.top;
      var thisMaxX = offset.left + $e.outerWidth();
      var thisMaxY = offset.top + $e.outerHeight();
      minX = Math.min(minX || thisMinX, thisMinX);
      minY = Math.min(minY || thisMinY, thisMinY);
      maxX = Math.max(maxX || thisMaxX, thisMaxX);
      maxY = Math.max(maxY || thisMaxY, thisMaxY);
    });
    if(true) {
      minX = minX - 10;
      minY = minY - 10;
      maxX = maxX + 10;
      maxY = maxY + 10;
    }
    var settings = modal.highlight_settings || Ember.Object.create();
    settings.setProperties({
      left: Math.floor(minX),
      top: Math.floor(minY),
      width: Math.ceil(maxX - minX),
      height: Math.ceil(maxY - minY),
      bottom: Math.floor(maxY),
    });

    options = options || {};
    settings.set('overlay', options.overlay);
    if(settings.get('overlay') !== false) { settings.set('overlay', true); }
    settings.set('clear_overlay', options.clear_overlay);
    settings.set('prevent_close', options.prevent_close);
    settings.set('select_anywhere', options.select_anywhere);
    settings.set('defer', Ember.RSVP.defer());
    var promise = settings.get('defer').promise;

    if(modal.highlight_controller) {
      if(modal.highlight_promise) {
        modal.highlight_promise.reject('closing due to new highlight');
      }
      modal.highlight_controller.set('model', settings);
    } else {
      modal.close();
      Ember.run.later(function() {
        modal.open('highlight', settings);
      });
    }
    modal.highlight_promise = settings.get('defer');
    modal.highlight_settings = settings;
    return promise;
  },
  close_highlight: function() {
    if(this.last_template == 'highlight') {
      modal.close();
    }
  },
  close: function(success) {
    if(!this.route) { return; }
    if(this.last_promise) {
      if(success || success === undefined) {
        this.last_promise.resolve(success);
      } else {
        this.last_promise.reject('force close');
      }
      this.last_promise = null;
    }
    if(this.highlight_promise) {
      this.highlight_promise.reject('force close');
      this.highlight_promise = null;
    }
    if(this.resume_scanning) {
      var _this = this;
      Ember.run.later(function() {
        if(!modal.is_open()) {
          _this.resume_scanning = false;
          scanner.start();
        }
      });
    }
    this.last_template = null;
    if(this.route.disconnectOutlet) {
      if(this.last_controller && this.last_controller.closing) {
        this.last_controller.closing();
      }
      this.route.disconnectOutlet({
        outlet: 'modal',
        parentView: 'application'
      });
    }
    if(this.queued_template) {
      Ember.run.later(function() {
        if(!modal.is_open()) {
          modal.open(modal.queued_template);
          modal.queued_template = null;
        }
      }, 2000);
    }
  },
  flash: function(text, type, below_header, sticky, opts) {
    if(!this.route) { throw "must call setup before trying to show a flash message"; }
    type = type || 'notice';
    this.route.disconnectOutlet({
      outlet: 'flash-message',
      parentView: 'application'
    });
    this.settings_for['flash'] = {type: type, text: text, sticky: sticky};
    if(below_header) {
      this.settings_for['flash'].below_header = below_header;
    }
    if(opts && opts.subscribe_redirect) {
      this.settings_for['flash'].subscribe = true;
    }

    var _this = this;
    Ember.run.later(function() {
      var timeout = below_header ? 500 : 1500;
      modal.route.render('flash-message', { into: 'application', outlet: 'flash-message'});
      if(!sticky) {
        Ember.run.later(function() {
          _this.fade_flash();
        }, timeout);
      }
    });
  },
  fade_flash: function() {
    Ember.$('.flash').addClass('fade');
  },
  warning: function(text, below_header, sticky, opts) {
    modal.flash(text, 'warning', below_header, sticky, opts);
  },
  error: function(text, below_header, sticky, opts) {
    modal.flash(text, 'error', below_header, sticky, opts);
  },
  notice: function(text, below_header, sticky, opts) {
    modal.flash(text, 'notice', below_header, sticky, opts);
  },
  success: function(text, below_header, sticky, opts) {
    modal.flash(text, 'success', below_header, sticky, opts);
  }
}).create();

modal.ModalController = Ember.Controller.extend({
  actions: {
    opening: function() {
      var template = this.get('templateName') || this.get('renderedName') || this.constructor.toString().split(/:/)[1];
      var settings = modal.settings_for[template] || {};
      var controller = this;
      modal.last_controller = controller;
      controller.set('model', settings);
      if(controller.opening) {
        controller.opening();
      }
    },
    closing: function() {
      if(this.closing) {
        this.closing();
      }
    },
    close: function() {
      modal.close();
    }
  }
});

// global var required for speech.js library
// TODO: fix speech.js library to not need to have global var
window.modal = modal;

export default modal;
