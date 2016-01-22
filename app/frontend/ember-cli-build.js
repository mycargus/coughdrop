/* global require, module */
var EmberApp = require('ember-cli/lib/broccoli/ember-app');

module.exports = function(defaults) {
  var app = new EmberApp(defaults, {
    storeConfigInMeta: false,
    vendorFiles: {
      'handlebars.js': null,
      'ember.js': 'bower_components/ember/ember.prod.js',
      'ember-data.js': 'bower_components/ember-data/ember-data.prod.js'
    },
    fingerprint: {
      enabled: false
    },
    minifyJS: {
      enabled: false
    }
  });

  // Use `app.import` to add additional libraries to the generated
  // output files.
  //
  // If you need to use different assets in different
  // environments, specify an object as the first parameter. That
  // object's keys should be the environment name and the values
  // should be the asset to use in that environment.
  //
  // If the library that you are including contains AMD or ES6
  // modules that you would like to import into your application
  // please specify an object with the list of modules as keys
  // along with the exports of each module as its value.
  app.import('bower_components/IndexedDBShim/dist/indexeddbshim.min.js');
  app.import('bower_components/moment/moment.js');
  app.import('bower_components/tinycolor/tinycolor.js');
  app.import('bower_components/jquery-minicolors/jquery.minicolors.min.js');
  app.import('bower_components/bootstrap/dist/js/bootstrap.min.js');
  app.import('bower_components/recordrtc/RecordRTC.min.js');
  app.import('bower_components/wordcloud2.js/src/wordcloud2.js');
  app.import('vendor/media_recorder/media_recorder.js');
  app.import('vendor/speak_js/speakClient.js');
  app.import('vendor/speech/speech.js');
//  app.import('bower_components/hammer-time/hammer-time.js');

  return app.toTree();
};
