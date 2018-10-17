## CoughDrop - Every Voice Should Be Heard

CoughDrop is an open, web-based AAC (Augmentative and Alternative Communication) app. Basically
if people struggle getting their words out for whatever reason, they can use
the speech synthesis engine on a computing device to "speak" for them. Sometimes
they'll just type on a keyboard (think Stephen Hawking), but sometimes typing is too slow
or not a reasonable expectation, so communication
"boards", which are just grids of labeled pictures, can also be used. CoughDrop supports
building these grids and keyboards, optionally tracks their usage, and also offers
tools for the team supporting the communicator.

CoughDrop is web-based, and will run on most modern browsers. You can try it out
for free at https://www.mycoughdrop.com. It leverages modern web standards like the
Web Speech API, the Application Cache, IndexedDB and a bunch of HTML5 to work
both online and offline. It should run on Windows, Mac, ChromeOS, iOS and Android, and can
be packaged up for app stores as well.

Unlike most other AAC apps, which are installed and live on a single device, CoughDrop
is cloud-based, and syncs edits across multiple devices automatically. This may seem 
unimportant, but when you spend a lot of time building a very personalized vocabulary,
you don't want a broken device or a dead battery to prevent you from communicating. With
CoughDrop you can just log into a different device and keep going.

Additionally, CoughDrop allows users to add "supervisors", which are administrative
users that can help modify boards, track usage reports, and coordinate strategy. In the
past users would have to hand over their device so therapists or parents could make
changes or review usage logs, but with CoughDrop supervisors can do their thing on their
own devices. And permission controls always stay in the hands of the user.

Anyway, that's CoughDrop in a nutshell. The code is open source so you're free to
run it yourself. We require a code contributor agreement before accepting changes into
our repo. Boards created in CoughDrop use the Open Board Format (http://www.openboardformat.org)
so they should export/import across instances of CoughDrop and a few other systems
without having to dig around in the database.

### Technical Notes

CoughDrop has a Rails backend (`/`) and an Ember frontend (`/app/frontend`), which are 
both contained in this
repository. If you're familiar with those frameworks then hopefully nothing here will
embarrass me too much -- ...I mean, hopefully you'll be able to pick up pretty quickly
the basic makeup of the app. These notes are not comprehensive, Feel free to help
me flesh them out if that's your thing.

The frontend and backend communicate via the open and completely-undocumented API.

#### Backend Setup

Dev dependencies: ruby, Postgres, Redis, Node, ember-cli

The backend relies on Redis and Postgres both being installed. Both are required in 
development and production. If 
you have ruby installed in your environment, you'll need the bundler gem:

```
gem install bundler
```

After that you can install ruby dependencies with:

```
bundle install
```

Next, you'll need to set some environment variables. The easiest way to do this
is with a `.env` file:

```
cp .env.example .env
```

You'll need to uncomment (remove the "# " at the beinning of) 
the first group of variables since they're required. For the `REDIS_URL` line,
enter a valid redis url (default would be `REDIS_URL=redis://localhost:6379/`). 
Then update
`config/database.yml` to match your settings (the defaults may work fine) if you
setup a vanilla postgres instance.

<i>Redis quickstart: https://redis.io/topics/quickstart</i>

Next you'll want to setup your database. Before you can do that, you'll need to address
a couple of dangling symbolic links, but we have a command to help with that. 
Here's the sequence that should work:

```
rails extras:assert_js
rails db:create
rails db:migrate
rails db:seed
```

You can skip the last command if you want, it'll populate with some bootstrap data including
a login, `example` and `password` to get you started.

Once the database is created, you can start the server. If you run `rails server` you
can start a single server process and hit it up in your browser at the default address
(`http://localhost:3000` or whatever you changed it to). You'll be stuck on the
loading page because the frontend hasn't compiled the frontend javascript yet.

#### Frontend Setup

The frontend is an ember app. I recommend installing ember-cli (https://ember-cli.com/user-guide/)
to make your life easier. Once you've got ember-cli installed, run:

```
cd app/frontend
npm install
bower install
```
To download all the app dependencies at once. It'll ask you about modifying files, 
if you're not sure what to do enter "n" if it asks about replacing a file. Otherwise
you can check the diffs and see what you'd like to keep/change.

Once you have the dependencies downloaded, then any code changes within `frontend` should
automatically regenerate `frontend.js` which is what the Rails app makes sure to deliver
to the browser.

#### Running the Full System
CoughDrop has more than one process needed for things to run correctly. You can look in 
`Procfile` for the commands we use to run a web server or a resque (background job) server.
The ember process is for development. It auto-compiles code as it's written, and shouldn't
be run in production. The easiest way to get things up and running is with the foreman gem:

```
gem install foreman
foreman start
```

That'll run one instance of each process in the Procfile, which is more than you need
but it'll work. After you start the ember process, it'll probably take around a minute or so for
it to compile the javascript for the first time. You should see some notes on the console
about a successful build, then you can reload your browser and see the welcome page. You
should be able to log in and go to town.

##### Additional Dependencies

In order to support generating utterances for sharing,  downloading pdfs, and uploading
images, you'll need to have
ImageMagick (`convert`, `identify`, `montage`), rsvg-convert and Node (`node`) 
installed in the execution path. There are also a number of server-side integrations you
can install that require secure keys, they are listed in `.env.example` with explanations
of where they are required. Note that if you're trying to run a production environment, 
not all functionality will degrade gracefully without these environment variables.

There are also some rake tasks you'll want to schedule to run periodically. I use 
Heroku Scheduler to run them at the specified frequency:

```
rake check_for_expiring_subscriptions (run daily)
rake generate_log_summaries (run hourly)
rake push_remote_logs (run hourly)
rake transcode_errored_records (run daily)
```

### License

Copyright (C) 2014-2017 CoughDrop, Inc.

Licensed under the AGPLv3 license.
