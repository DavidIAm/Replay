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


State data model

Domain (to be implimented)
 Rule
 * version
  * window
   * key
    * atom

Business Rule
 * match
 * indow
 * ersion
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
   * uses summarize method of business rule to format window documents to
      * summary
   * store in ReportStore
   * emits on control channel 'NewSummary'
* Clerk
 * to be implemented
 * probably a REST service consumed by mashups and client programs
 * poorly defined functionality regarding comparing disparate windows and
    * versions

