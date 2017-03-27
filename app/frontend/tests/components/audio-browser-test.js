import DS from 'ember-data';
import Ember from 'ember';
import { test, moduleForModel, moduleForComponent } from 'ember-qunit';
import { describe, it, expect, beforeEach, afterEach, waitsFor, runs, stub } from 'frontend/tests/helpers/jasmine';
import { queryLog } from 'frontend/tests/helpers/ember_helper';
import CoughDrop from '../../app';
import persistence from '../../utils/persistence';
import modal from '../../utils/modal';
import audioBrowser from '../../components/audio-browser';
import Button from '../../utils/button';

describe('audio-browser', function() {
  moduleForComponent('audio-browser', 'test', {unit: true});
  var component = null;
  beforeEach(function() {
    component = this.subject();
  });

  it('should have specs', function() {
    expect(component).not.toEqual(null);
    expect('test').toEqual('todo');
  });
});
//
//
//   describe("browse_audio", function() {
//     it('should set status correctly', function() {
//       soundGrabber.setup(button, controller);
//       var called = false;
//       app_state.set('currentUser', {id: 'bob'});
//       stub(Utils, 'all_pages', function(type, params, progress) {
//         called = true;
//         expect(type).toEqual('sound');
//         expect(params).toEqual({user_id: 'bob'});
//         return Ember.RSVP.resolve([]);
//       });
//       soundGrabber.browse_audio();
//       expect(controller.get('browse_audio')).toEqual({loading: true});
//       waitsFor(function() { return controller.get('browse_audio.loading') == null; });
//       runs(function() {
//         expect(called).toEqual(true);
//         expect(controller.get('browse_audio')).toEqual({results: [], full_results: [], filtered_results: []});
//       });
//     });
//
//     it('should lookup all results', function() {
//       soundGrabber.setup(button, controller);
//       app_state.set('currentUser', {id: 'bob'});
//       var called = false;
//       stub(Utils, 'all_pages', function(type, params, progress) {
//         called = true;
//         expect(type).toEqual('sound');
//         expect(params).toEqual({user_id: 'bob'});
//         return Ember.RSVP.resolve([]);
//       });
//       soundGrabber.browse_audio();
//       expect(controller.get('browse_audio')).toEqual({loading: true});
//       waitsFor(function() { return controller.get('browse_audio.loading') == null; });
//       runs(function() {
//         expect(called).toEqual(true);
//         expect(controller.get('browse_audio')).toEqual({results: [], full_results: [], filtered_results: []});
//       });
//     });
//
//     it('should error correctly', function() {
//       soundGrabber.setup(button, controller);
//       app_state.set('currentUser', {id: 'bob'});
//       var called = false;
//       stub(Utils, 'all_pages', function(type, params, progress) {
//         called = true;
//         expect(type).toEqual('sound');
//         expect(params).toEqual({user_id: 'bob'});
//         return Ember.RSVP.reject([]);
//       });
//       soundGrabber.browse_audio();
//       expect(controller.get('browse_audio')).toEqual({loading: true});
//       waitsFor(function() { return controller.get('browse_audio.loading') == null; });
//       runs(function() {
//         expect(called).toEqual(true);
//         expect(controller.get('browse_audio')).toEqual({error: true});
//       });
//     });
//   });
//
//   describe("filter_browsed_audio", function() {
//     it('should return a filtered list', function() {
//       soundGrabber.setup(button, controller);
//       controller.set('browse_audio', {
//         full_results: [
//           Ember.Object.create({search_string: 'hat is good'}),
//           Ember.Object.create({search_string: 'hat is bad'}),
//           Ember.Object.create({search_string: 'hat is swell'}),
//           Ember.Object.create({search_string: 'hat is neat'}),
//           Ember.Object.create({search_string: 'hat is something'}),
//           Ember.Object.create({search_string: 'hat is ok'}),
//           Ember.Object.create({search_string: 'hat is awesome'}),
//           Ember.Object.create({search_string: 'hat is cheese'}),
//           Ember.Object.create({search_string: 'splat is cool'}),
//           Ember.Object.create({search_string: 'hat is from'}),
//           Ember.Object.create({search_string: 'hat is windy'}),
//           Ember.Object.create({search_string: 'hat is above'}),
//           Ember.Object.create({search_string: 'hat is flat'}),
//         ]
//       });
//       soundGrabber.filter_browsed_audio('hat');
//       expect(controller.get('browse_audio.filtered_results.length')).toEqual(12);
//       expect(controller.get('browse_audio.results.length')).toEqual(10);
//     });
//   });
//
//   describe("more_browsed_audio", function() {
//     it('should add to the list', function() {
//       soundGrabber.setup(button, controller);
//       var list = [];
//       for(var idx = 0; idx < 100; idx++) {
//         list.push(Ember.Object.create());
//       }
//
//       controller.set('browse_audio', {
//         results: list.slice(0, 5),
//         filtered_results: list.slice(0, 30),
//         full_results: list
//       });
//       soundGrabber.more_browsed_audio();
//       expect(controller.get('browse_audio.results.length')).toEqual(15);
//       expect(controller.get('browse_audio.filtered_results.length')).toEqual(30);
//       soundGrabber.more_browsed_audio();
//       expect(controller.get('browse_audio.results.length')).toEqual(25);
//       expect(controller.get('browse_audio.filtered_results.length')).toEqual(30);
//       soundGrabber.more_browsed_audio();
//       expect(controller.get('browse_audio.results.length')).toEqual(30);
//       expect(controller.get('browse_audio.filtered_results.length')).toEqual(30);
//     });
//
//     it('should do nothing if already fully loaded', function() {
//       soundGrabber.setup(button, controller);
//       var list = [];
//       for(var idx = 0; idx < 100; idx++) {
//         list.push(Ember.Object.create());
//       }
//
//       controller.set('browse_audio', {
//         results: list,
//         filtered_results: list.slice(0, 30),
//         full_results: list
//       });
//       soundGrabber.more_browsed_audio();
//       expect(controller.get('browse_audio.results.length')).toEqual(30);
//       expect(controller.get('browse_audio.filtered_results.length')).toEqual(30);
//     });
//   });
//
//   describe("select_browsed_audio", function() {
//     it('should update correctly', function() {
//       soundGrabber.setup(button, controller);
//       controller.set('browse_audio', {loading: true});
//       soundGrabber.select_browsed_audio('asdf');
//       expect(controller.get('browse_audio')).toEqual(null);
//       expect(controller.get('model.sound')).toEqual('asdf');
//     });
//   });
