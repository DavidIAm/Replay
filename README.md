Replay
======

#Perl implimentation of Replay idea

This concept is an original development of David Ihnen, refined with
many thanks through discussions with Glen Hinkle.

TL;DR? - bitemporal finite state machine application engine modular down
to the fundamental state transition level using a variant of map-reduce
methodology with the goal of making instrospection, revision, and proofing
native rather than derivative in a fully scalable architecture

Bitemporality is the concept that things have an effective date, as well
as a first-heard-about or action date.

Imagine an application as a finite state machine. Shouldn't be hard,
because that is what most are.

A state's transitions are determined by a business rule of a particular
version configured in a domain.  We will have many business rules.
There will be different time groups relevant for each new input that
arrives. The rule can extract the relevant bits from the event for its
own state transitions, grouping them by key.

Imagine that those atomic pieces of state were divided into bins by
domain, rule, version, window, and key

Each state transition is detectable by examining only the atoms under
a single key bin.

State transitions have many layers, so when a state transition is
detected, another event can be emitted, which can be processed by still
other rules.

Imagine your system output has a metadata component that will inform you
of every business rule and version used, along with enough information
to derive all of the original input that was given to it.  This will
make it plenty easy to debug, don't you think?  Its like every report
coming with a trace and input log!

Imagine you are repairing a bug you accidentally introduced last week.
It has mucked up your reports and output.  Imagine that you could change
your repaired code's effective date to *last week*. The snapshot and
replay capability will not only allows you to see how your new code works
with your old input - but you can do so for testing or proof without
interrupting your production systems.  AND you can automatically get a
complete and exhaustive report on how your system's reports have changed
*solely* as a matter of the change. Auditability and proof of correct
operation, anyone?

Now imagine you missed a series of transactions for your books that
happened months ago, books that are now of course closed.  What a
mess, right?  All the corrections can be a neverending rabbit warren.
This system allows the separation of backdated effective information
from the previously frozen reports.  Individual, per-account reports on
the changes that are introduced by the backdated information generated
automatically per the original business rules with no manual intervention
or research required.

Imagine you need a bit of instrumentation in your application, to
check into the rate of change of a particular state. Easy-peasy - all
the states of the application are available, all the state transitions
are on an event bus. Add a new business rule that reduces out to the
appropriate instrumentation report, subscribe your monitoring system
to the external event stream and *boom* - instant application metrics
available in near-time in your monitoring
	application of choice.

Bear with me while I go over some of the structures and pieces here:

![Replay diagram](images/Replay%20Report%20System.png)

State data model

##IdKey
 * Domain (to be implimented)
   * Rule
     * version
       * window
         * key
           * atom

##Business Rule
 * match
 * window
 * version
 * compare
 * keyValueSet
 * reduce
 * deliver
 * summarize

##Event Channels
 * origin - new input to the application space
 * derived - application data state transitions
 * control - framework state transitions

##Components

### Worm 
 * to be implimented 
 * listens to all origin events
 * writes event log
 * tags with replay window
 * emits derived events

### StorageEngine 
 * absorb new atoms
   * uses 'compare' business rule method to sort
   * emits on control channel 'Reducable'
   * unaffected by locks
 * checkout state document
   * locks against other checkouts
   * emits on control channel 'Reducing'
 * checkin state document
   * emits on control channel 'NewCanonical'
   * when more is still reducable, emits on control channel 'Reducable'
   * unlocks for further checkouts
 * retrieve state document
   * emits on control channel 'Fetched'
   * unaffected by locks
 * windowAll keys and their states for a window
   * emits on control channel 'WindowAll'
 * snapshot
   * to be implemented
   * create the ability to revert to this current state across the entire domain.

### Mapper 
 * listens to all derived events
 * uses match method of business rule to determine relevancy
 * uses window method of business rule to tag time grouping
 * uses version method of business rule to tag rule version
 * uses keyValueSet method of business rule to translate into key groups and atoms
 * presents new atoms for absorb by storage engine
 * Reducer
 * listens to control events
 * when hears Reducable attempts to checkout from storage
   * merges previous canonical state with new atoms
   * uses reduce method of business rule to reduce merged atoms to new state
     * business rule may emit new messages encapsulating state transitions on 
        * derived channel
   * checks in new state to storage

### RuleSource
 * encapsulates the rules available to the system

### ReportStore
 * to be implemented
 * store - update the current working copy
 * freeze - preserve the current copy as a revision 
 * retrieve - deliver the requested revision

### Bureaucrat
 * to be implemented
 * listens to control channel 'NewCanonical' events
   * retrieve state from StorageEngine
   * uses deliver method of business rule to format key state to deliverable
      * form
   * store in ReportStore
   * emits on control channel 'NewReport'
 * listens to control channel 'NewReport' events
   * windowAll state from StorageEngine
   * uses summarize method of business rule to format window documents to store in ReportStore
   * emits on control channel 'NewSummary'

### Clerk
 * to be implemented
 * probably a REST service consumed by mashups and client programs
 * poorly defined functionality regarding comparing disparate windows and
    * versions

### Replay
 * to be implemented
 * listens on the control channel
 * upon appropriate signal event, reads some sequence of information previously
	 recorded from the WORM into the derived event channel of the indicated domain.

### SubscriptionService
 * to be implemented
 * listens on the control channel
 * handles external requests regarding interesting transitions, makes
	 Rest/queue/whatever sorts of actions in response to internal system messages


##How it works

Thanks, I know that was long and confusing.  What does it all mean?
How does it work?  Let me walk you through.

An origin event enters the system.  Anything of interest not generated
externally is origin.

WORM listens to origin channel and will record this event in the worm, tag it with when it recorded it, and emit it on the derived channel as a state transition

Mapper listens to the derived channel it uses the ruleSource to iterate across
the rules.  it compares the message to each rule by passing it to the match 
method.  when it matches, it gets the window value from that method, and the 
list of keys and atoms from the keyValueSet method.  it then calls the
storageEngine to absorb these atoms

StorageEngine absorbs the values using 'compare' portion of the rule to insert
the value and emits 'reducable' on control channel indicating that a state has 
new input, is thus available for state transition processing

Reducer hears that there is a reducable state available and attempts to
checkout the state from the storageengine

The storage engine locks the record atomically then merges the canonical atom list
with the inbox atom list to create a desktop atom list and returns this to the
reducer

the reducer uses the 'reduce' function to reduce this list to a canonical set.  
It makes available the ability to generate state transitions detected during the 
processing of the atoms on the derived channel.  Once reduced, the state is checked back to the storage engine

The storage engine saves and unlocks the change and emits a 'NewCanonical' on
the control channel 

on success of checkin The reducer emits all the state transitions generated
during the reduce on the derived channel

Bureaucrat listens to the control channel for 'NewCanonical'.  When it hears
one, it retrieves the state from the StorageEngine

The storageEngine returns the canonical state with no locking delay.

Thebeurocrat uses rule portion 'deliver' to render a report out of the
canonical atom list and stores it in ReportStore

ReportStore saves the report in a way which an external REST service may
retrieve it on a high speed cached low processing mostly static basis.  When the report is stored, ReportStore emits 'NewReport' on the control channel

The bureaucrat listens to the control channel for 'NewReport'.  When it hears
one, it retrieves all of the reports for the particular window from the
ReportStore.  It uses the summary business rule method to create a summary.
The summary is stored in the ReportStore

The report store saves the summary in a way which an external REST service may
retrieve it on a high speed cached low processing mostly static basis.  When
the summary is stored, ReportStore emits 'NewSummary' on the control channel

The subscription Service listens on the control channel for whatever it is
configured to listen for as a REST service and worker.  Lets say it was
configured to trigger a remote cache update whenever a summary is updated.
SubscriptionService will match the NewSummary message and immediately call out
to the cache control service informing it which document is now invalid so that
it may be retrieved to the endpoints of the content delivery network - enabling
as many layers of cache as necessary.


