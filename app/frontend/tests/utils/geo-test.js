import { describe, it, expect, beforeEach, afterEach, waitsFor, runs, stub } from 'frontend/tests/helpers/jasmine';
import { fakeRecorder, fakeMediaRecorder, fakeCanvas, queryLog, easyPromise, queue_promise } from 'frontend/tests/helpers/ember_helper';
import RSVP from 'rsvp';
import app_state from '../../utils/app_state';
import Ember from 'ember';
import EmberObject from '@ember/object';
import geo from '../../utils/geo';
import stashes from '../../utils/_stashes';
import persistence from '../../utils/persistence';

describe('geo', function() {
  it("should correctly measure distances", function() {
    expect(geo.distance(40.571457,-112.0085445,40.5825151,-111.9165105)).toEqual(25818.555538053763);
    expect(geo.distance(40.5825477,-111.9178624,40.5825151,-111.9165105)).toEqual(374.75192559336193);
    expect(geo.distance(1,1,1.0001,1.0001)).toEqual(51.58885857662891);
  });

  describe("check_locations", function() {
    beforeEach(function() {
      geo.set('last_location_check', null);
    });

    it("should do nothing if no location data available", function() {
      stashes.set('geo.latest', null);
      var done = true;
      geo.check_locations().then(null, function() { done = true; });
      waitsFor(function() { return done; });
      runs();
    });

    it("should ping if not already pinging", function() {
      app_state.set('currentUser', EmberObject.create({user_name: 'bob'}));
      stub(persistence, 'ajax', function(url, opts) {
        if(url == '/api/v1/users/bob/places?latitude=1&longitude=1') {
          return RSVP.resolve([]);
        } else {
          return RSVP.reject();
        }
      });
      stashes.set('geo.latest', {coords: {latitude: 1, longitude: 1}});
      var done = false;
      geo.check_locations().then(function(res) { done = res; });
      waitsFor(function() { return done; });
      runs(function() {
        expect(done).toEqual([]);
      });
    });

    it("should error on failed ajax call", function() {
      app_state.set('currentUser', EmberObject.create({user_name: 'bob'}));
      stub(persistence, 'ajax', function(url, opts) {
        return RSVP.reject({error: 'bad stuff'});
      });
      stashes.set('geo.latest', {coords: {latitude: 1, longitude: 1}});
      var done = false;
      geo.check_locations().then(null, function(res) { done = res; });
      waitsFor(function() { return done; });
      runs(function() {
        expect(done).toEqual({error: 'bad stuff'});
      });
    });

    it("should not ping if already pinging", function() {
      app_state.set('currentUser', EmberObject.create({user_name: 'bob'}));
      var defer = RSVP.defer();
      stub(persistence, 'ajax', function(url, opts) {
        if(url == '/api/v1/users/bob/places?latitude=1&longitude=1') {
          return defer.promise;
        } else {
          return RSVP.reject();
        }
      });
      stashes.set('geo.latest', {coords: {latitude: 1, longitude: 1}});
      var done = false;
      var done2 = false;
      geo.check_locations().then(function(res) { done = res; });
      geo.check_locations().then(null, function() { done2 = true; defer.resolve([]); });
      waitsFor(function() { return done && done2; });
      runs(function() {
        expect(done).toEqual([]);
      });
    });

    it("should not ping if not far enough away from the last ping", function() {
      app_state.set('currentUser', EmberObject.create({user_name: 'bob'}));
      stub(persistence, 'ajax', function(url, opts) {
        return RSVP.reject();
      });
      stashes.set('geo.latest', {coords: {latitude: 1, longitude: 1}});
      var done = false;
      geo.set('last_location_check', {latitude: 1.0001, longitude: 1.0001});
      geo.check_locations().then(null, function(err) { done = err; });
      waitsFor(function() { return done; });
      runs(function() {
        expect(done).toEqual({error: "nothing to check"});
      });
    });

    it("should update nearby_places with the result", function() {
      app_state.set('nearby_places', []);
      app_state.set('currentUser',EmberObject.create({user_name: 'bob'}));
      stub(persistence, 'ajax', function(url, opts) {
        if(url == '/api/v1/users/bob/places?latitude=1&longitude=1') {
          return RSVP.resolve([1, 2, 3]);
        } else {
          return RSVP.reject();
        }
      });
      stashes.set('geo.latest', {coords: {latitude: 1, longitude: 1}});
      var done = false;
      geo.check_locations().then(function(res) { done = res; });
      waitsFor(function() { return done; });
      runs(function() {
        expect(done).toEqual([1, 2, 3]);
        expect(app_state.get('nearby_places')).toEqual([1, 2, 3]);
      });
    });
  });
});
