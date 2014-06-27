Replay
======

Perl implimentation of Replay idea

TL;DR? - finite state machine application engine modular down to the basic
state transition level

Imagine an application as a finite state machine.

Each state of the program consists of a series of atoms that are relevant to
that state, grouped by window and key.

Those which are relevant to each other in time have the same window. 

Those which are relevant to each other for state transition purposes have the
same key.

A state's transitions are determined by a business rule.  We will have many
business rules.

Bear with me while I go over some of the structures and pieces here:

![Replay diagram](Replay diagram)

State data model

IdKey
 * Domain (to be implimented)
   * Rule
     * version
       * window
         * key
           * atom

Business Rule
 * match
 * window
 * version
 * compare
 * keyValueSet
 * reduce
 * deliver
 * summarize

Event Channels
 * origin - new input to the application space
 * derived - application data state transitions
 * control - framework state transitions

Components
* Worm 
 * to be implimented 
 * listens to all origin events
 * writes event log
 * tags with replay window
 * emits derived events
* StorageEngine 
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
* Mapper 
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
* RuleSource
 * encapsulates the rules available to the system
* ReportStore
 * to be implemented
 * store - update the current working copy
 * freeze - preserve the current copy as a revision 
 * retrieve - deliver the requested revision
* Bureaucrat
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
* Clerk
 * to be implemented
 * probably a REST service consumed by mashups and client programs
 * poorly defined functionality regarding comparing disparate windows and
    * versions
* Replay
 * to be implemented
 * listens on the control channel
 * upon appropriate signal event, reads some sequence of information previously
	 recorded from the WORM into the derived event channel of the indicated domain.
* SubscriptionService
 * to be implemented
 * listens on the control channel
 * handles external requests regarding interesting transitions, makes
	 Rest/queue/whatever sorts of actions in response to internal system messages

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

![Replay diagram]: images/Replay%20Report%20System.png

