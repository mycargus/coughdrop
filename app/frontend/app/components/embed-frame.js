import Ember from 'ember';
import frame_listener from '../utils/frame_listener';
import i18n from '../utils/i18n';
import persistence from '../utils/persistence';

export default Ember.Component.extend({
  tagName: 'div',
  classNames: ['integration_container'],
  didInsertElement: function() {
    var elem = this.element;
    this.element.addEventListener('mousemove', function(event) {
      if(elem) {
        var session_id = elem.childNodes[0].getAttribute('data-session_id');
//         frame_listener.raw_event({
//           session_id: session_id,
//           type: 'mousemove',
//           x_percent: 0.1,
//           y_percent: 0.2
//         });
      }
    });
    this.element.addEventListener('click', function(e) {
      if(elem) {
        var session_id = elem.childNodes[0].getAttribute('data-session_id');
//         frame_listener.raw_event({
//           session_id: session_id,
//           type: 'click',
//           x_percent: 0.3,
//           y_percent: 0.325
//         });
      }
    });
    Ember.run.later(function() {
      if(Ember.$(elem).find("#integration_overlay.pending").length > 0) {
        Ember.$(elem).find("#integration_overlay .status").text(i18n.t('loading_integration', "Loading Integration..."));
      }
    }, 750);
    Ember.run.later(function() {
      if(Ember.$(elem).find("#integration_overlay.pending").length > 0) {
        if(!persistence.get('online')) {
          Ember.$(elem).find("#integration_overlay .status").text(i18n.t('loading_integration_failed_offline', "Integrations cannot load when offline"));
        } else {
          Ember.$(elem).find("#integration_overlay .status").text(i18n.t('loading_integration_failed', "Integration hasn't loaded, please check your settings and Internet Connection"));
        }
      }
    }, 5000);
  },
  overlay_style: function() {
    var res = this.get('board_style');
    res = res.string || res;
    if(res && res.replace) {
      res = res.replace(/position:\s*relative/, 'position: absolute');
    }
    return Ember.String.htmlSafe(res);
  }.property('board_style'),
  actions: {
  }
});
