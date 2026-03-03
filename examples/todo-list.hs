{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
module Main where

-- | A task with a title, description, and completion status (done or not done).
data Task = Task
  { taskTitle       :: String
  , taskDescription :: String
  , taskDone        :: Bool
  } deriving (Show, Eq)

-- | A collection of tasks.
newtype TodoList = TodoList [Task] deriving (Show, Eq)

-- | Creates an empty to-do list with no tasks.
emptyTodoList :: TodoList
emptyTodoList = TodoList []

-- | Adds a task to the to-do list.
addTask :: Task -> TodoList -> TodoList
addTask task (TodoList tasks) = TodoList (tasks ++ [task])

-- | Marks a task as complete by matching its title. Sets taskDone to True for the matching task.
markComplete :: String -> TodoList -> TodoList
markComplete title (TodoList tasks) = TodoList (map markIfMatch tasks)
  where
    markIfMatch t
      | taskTitle t == title = t { taskDone = True }
      | otherwise            = t

-- | Formats a single task for display, using "[x]" for done and "[ ]" for not done, followed by the task title.
formatTask :: Task -> String
formatTask t =
  let status = if taskDone t then "[x]" else "[ ]"
  in status ++ " " ++ taskTitle t

-- | Extracts the list of tasks from a TodoList.
getTasks :: TodoList -> [Task]
getTasks (TodoList tasks) = tasks

-- | Displays all tasks in the to-do list, showing their completion status.
displayTasks :: TodoList -> IO ()
displayTasks todoList = mapM_ (putStrLn . formatTask) (getTasks todoList)

-- | Main entry point: creates a to-do list with sample tasks, marks one complete, and displays all tasks.
main :: IO ()
main = do
  let list0 = emptyTodoList
  let list1 = addTask (Task "Buy groceries" "" False) list0
  let list2 = addTask (Task "Write report" "" False) list1
  let list3 = addTask (Task "Exercise" "" False) list2
  let list4 = markComplete "Buy groceries" list3
  displayTasks list4
```

