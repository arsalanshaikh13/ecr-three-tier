"use server";

import { connectToDatabase } from "@/lib/mongodb";
import Task from "@/models/Task";
import { ITask } from "@/models/Task";
import { verifySession } from "./dal";
import { can } from "./utils";

/**
 * Get all tasks for the authenticated user
 */
export async function getTasksAction(userId: string): Promise<ITask[]> {
  try {
    const { user } = await verifySession();
    // if (!can(user, "read_tasks")) {
    //   throw new Error("You are not authorized to perform this action");
    // }
    if (!user) {
      throw new Error("Unauthorized: Please log in to view tasks.");
    }
    await connectToDatabase();

    if (!userId) {
      throw new Error("User ID is required");
    }

    const tasks = await Task.find({ createdBy: userId }).sort({
      createdAt: -1,
    });

    return JSON.parse(JSON.stringify(tasks));
  } catch (error) {
    console.error("Error fetching tasks:", error);
    throw error instanceof Error ? error : new Error("Failed to fetch tasks");
  }
}

/**
 * Create a new task
 */
export async function createTaskAction(taskData: {
  name: string;
  description?: string;
  dueDate?: string;
}): Promise<ITask> {
  try {
    const { user } = await verifySession();
    // if (!can(user, "create_tasks")) {
    //   throw new Error("You are not authorized to perform this action");
    // }

    if (!user) {
      throw new Error("Unauthorized: Please log in to create tasks.");
    }
    await connectToDatabase();

    const { name, description, dueDate } = taskData;

    if (!name || name.trim() === "") {
      throw new Error("Task name is required");
    }

    const task = new Task({
      name: name.trim(),
      description: description?.trim() || undefined,
      dueDate: dueDate || undefined,
      createdBy: user.id,
      completed: false,
    });

    await task.save();

    return JSON.parse(JSON.stringify(task));
  } catch (error) {
    console.error("Error creating task:", error);
    throw error instanceof Error ? error : new Error("Failed to create task");
  }
}

/**
 * Update an existing task
 */
export async function updateTaskAction(
  taskId: string,
  updates: {
    name?: string;
    description?: string;
    dueDate?: string;
    completed?: boolean;
  },
  userId: string,
): Promise<ITask> {
  try {
    const { user } = await verifySession();
    // if (!can(user, "update_tasks")) {
    //   throw new Error("You are not authorized to perform this action");
    // }
    if (!user) {
      throw new Error("You are not authorized to perform this action");
    }
    await connectToDatabase();

    if (!userId) {
      throw new Error("User ID is required");
    }

    const { name, description, dueDate, completed } = updates;

    // Verify user owns this task
    const task = await Task.findOne({
      _id: taskId,
      createdBy: userId,
    });

    if (!task) {
      throw new Error("Task not found or unauthorized");
    }

    // Update fields
    if (name !== undefined) task.name = name.trim();
    if (description !== undefined)
      task.description = description?.trim() || undefined;
    if (dueDate !== undefined) task.dueDate = dueDate || undefined;
    if (completed !== undefined) task.completed = completed;

    await task.save();

    return JSON.parse(JSON.stringify(task));
  } catch (error) {
    console.error("Error updating task:", error);
    throw error instanceof Error ? error : new Error("Failed to update task");
  }
}

/**
 * Delete a task
 */
export async function deleteTaskAction(
  taskId: string,
  userId: string,
): Promise<void> {
  try {
    const { user } = await verifySession();
    // if (!can(user, "delete_tasks")) {
    //   throw new Error("You are not authorized to perform this action");
    // }
    if (!user) {
      throw new Error("You are not authorized to perform this action");
    }
    await connectToDatabase();

    if (!userId) {
      throw new Error("User ID is required");
    }

    // Verify user owns this task before deleting
    const task = await Task.findOne({
      _id: taskId,
      createdBy: userId,
    });

    if (!task) {
      throw new Error("Task not found or unauthorized");
    }

    await Task.deleteOne({ _id: taskId, createdBy: userId });
  } catch (error) {
    console.error("Error deleting task:", error);
    throw error instanceof Error ? error : new Error("Failed to delete task");
  }
}

/**
 * Toggle task completion status
 */
export async function toggleTaskCompletionAction(
  taskId: string,
  currentStatus: boolean,
  userId: string,
): Promise<ITask> {
  return updateTaskAction(taskId, { completed: !currentStatus }, userId);
}
