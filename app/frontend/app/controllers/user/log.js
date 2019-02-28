import Ember from 'ember';
import Controller from '@ember/controller';
import { later as runLater } from '@ember/runloop';
import $ from 'jquery';
import i18n from '../../utils/i18n';
import modal from '../../utils/modal';
import capabilities from '../../utils/capabilities';
import CoughDrop from '../../app';

export default Controller.extend({
  title: function() {
    return "Log Details";
  }.property('model.user_name'),
  draw_charts: function() {
    if(!this.get('model.geo')) {
      return;
    }
    var user = this.get('user');
    var elem = document.getElementsByClassName('geo_map')[0];
    var geo = this.get('model.geo');
    if(user && user.get('preferences.geo_logging') && geo) {
        CoughDrop.Visualizations.wait('geo', function() {
          if(elem && geo) {
            var current_info = null;
            if(elem) {
              var map = new window.google.maps.Map(elem, {
                scrollwheel: false,
                maxZoom: 16
              });
              var markers = [];
              var locations = [geo];
              locations.forEach(function(location) {
                var title = i18n.t('session_count', "session", {count: location.total_sessions});
                var marker = new window.google.maps.Marker({
                  position: new window.google.maps.LatLng(location.latitude, location.longitude),
                  // TODO: https://developers.google.com/maps/documentation/javascript/examples/marker-animations-iteration
                  // animation: window.google.maps.Animation.DROP,
                  title: title
                });
                // TODO: popup information for each location
                marker.setMap(map);
                markers.push(marker);
              });
              var bounds = new window.google.maps.LatLngBounds();
              for(var i=0;i<markers.length;i++) {
               bounds.extend(markers[i].getPosition());
              }
              map.fitBounds(bounds);
            }
          }
        });
    }
  }.observes('model.geo', 'user'),
  actions: {
    reply: function() {
      var _this = this;
      var user = _this.get('user');
      modal.open('record-note', {note_type: 'text', user: user, prior: _this.get('model')});
    },
    lam_export: function() {
      capabilities.window_open('/api/v1/logs/' + this.get('model.id') + '/lam?nonce=' + this.get('model.nonce'), '_system');
    },
    obl_export: function() {
      modal.open('download-log', {log: this.get('model')});
    },
    toggle_notes: function(id, action) {
      this.get('model').toggle_notes(id);
      if(action == 'add') {
        runLater(function() {
          $("input[data-event_id='" + id + "']").focus().select();
        }, 200);
      }
    },
    add_note: function(event_id) {
      var val = $("input[data-event_id='" + event_id + "']").val();
      if(val) {
        this.get('model').add_note(event_id, val);
      }
      $("input[data-event_id='" + event_id + "']").val("");
    },
    highlight: function(event_id, do_highlight) {
        this.get('model').highlight(event_id, !!do_highlight);
    },
    draw_charts: function() {
      this.draw_charts();
    }
  }
});
