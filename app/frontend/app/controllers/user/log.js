import Ember from 'ember';
import Controller from '@ember/controller';
import { later as runLater } from '@ember/runloop';
import $ from 'jquery';
import i18n from '../../utils/i18n';
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

//           var geo = this.get('model.geo');
//       var done = function() {
//         var current_info = null;
//         var map = new window.google.maps.Map(document.getElementById('geo_map'), {
//           scrollwheel: false,
//           maxZoom: 18
//         });
//         var markers = [];
//
//         var title = i18n.t('session_location', "Log Entry Location");
//         var marker = new window.google.maps.Marker({
//           position: new window.google.maps.LatLng(geo.latitude, geo.longitude),
//           title: title
//         });
//         // TODO: popup information for each location
//         marker.setMap(map);
//         markers.push(marker);
//
//         var bounds = new window.google.maps.LatLngBounds();
//         for(var i=0;i<markers.length;i++) {
//          bounds.extend(markers[i].getPosition());
//         }
//         map.fitBounds(bounds);
//       };
//       if(geo) {
//         if(!window.google || !window.google.maps) {
//           window.ready_to_do_log_map = done;
//           var script = document.createElement('script');
//           script.type = 'text/javascript';
//           // TODO: pull api keys out into config file?
//           script.src = 'https://maps.googleapis.com/maps/api/js?v=3.exp&' +
//               'callback=ready_to_do_log_map&key=AIzaSyBofHMEAGEILQkXWAgO6fAbsLjw6fNJQwM';
//           document.body.appendChild(script);
//         } else {
//           runLater(done);
//         }
//       }
    }
  }.observes('model.geo', 'user'),
  actions: {
    lam_export: function() {
      capabilities.window_open('/api/v1/logs/' + this.get('model.id') + '/lam?nonce=' + this.get('model.nonce'), '_system');
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
    draw_charts: function() {
      this.draw_charts();
    }
  }
});
